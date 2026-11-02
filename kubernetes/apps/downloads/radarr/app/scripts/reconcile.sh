#!/usr/bin/env bash
# Clean up after Radarr/Sonarr on the external library. Both clear the read-only
# flag of a file before deleting it; on a Decypharr symlink that follows the link
# to the read-only TorBox mount and fails with EROFS, so:
# - an upgrade stays blocked in the queue because the old file cannot be deleted.
#   Drop the old links the app logged as undeletable while a download for the
#   title still waits: the next import retry skips the delete and moves the new
#   link with import.sh;
# - a deleted title leaves its folder behind. Remove folders the app no longer
#   knows that hold only links into the TorBox mount.
# Only links into the TorBox mount are ever removed, and no file is ever probed:
# reading a stalled TorBox file hangs on the hard NFS mount. DRY_RUN=true logs instead.
set -euo pipefail

app=${ARR_APP:?ARR_APP must be radarr or sonarr}
url=${ARR_URL:?}
library_root=${LIBRARY_ROOT:?}
media_root=${MEDIA_ROOT:-/data/external-media}
dry_run=${DRY_RUN:-false}
queue_page_size=${QUEUE_PAGE_SIZE:-2000}
# The app retries a blocked import every minute, so recent entries are enough.
log_page_size=${LOG_PAGE_SIZE:-1000}
# Skip folders changed recently: an import creates the folder before the title record.
orphan_min_age_minutes=${ORPHAN_MIN_AGE_MINUTES:-60}
# More orphans than this in one run points at a path mismatch, not at deletions.
max_orphans=${MAX_ORPHANS:-50}

# The API key reaches curl on stdin, so it never shows up in the process list.
api() { curl -fsS --max-time 300 -H @- "$url/api/v3/$1" <<<"X-Api-Key: ${ARR_API_KEY:?}"; }

is_media_link() { [[ -L "$1" && "$(readlink -- "$1")" == "$media_root"/* ]]; }

remove() {
  if [[ "$dry_run" == true ]]; then
    echo "would remove $1"
  else
    rm -rf -- "$1"
    echo "removed $1"
  fi
}

# Library files the titles point to now.
current_files() { # current_files <movie id | comma-separated episode ids>
  if [[ "$app" == radarr ]]; then
    api "moviefile?movieId=$1" | jq -r '.[].path'
  else
    api "episode?episodeIds=${1//,/&episodeIds=}&includeEpisodeFile=true" | jq -r '.[].episodeFile.path // empty'
  fi
}

# Completed downloads waiting to import, one per line: download id, then the
# movie id (Radarr) or the comma-separated episode ids (Sonarr lists one record
# per episode). A failed import cycles through all three states on every retry.
pending_downloads() {
  api "queue?pageSize=$queue_page_size" | jq -r --arg app "$app" '
    [.records[]
      | select(.status == "completed" and (.trackedDownloadState | IN("importPending", "importing", "importBlocked")))
      | select((if $app == "radarr" then .movieId else .episodeId end) != null)]
    | group_by(.downloadId)[]
    | [.[0].downloadId,
       (if $app == "radarr" then .[0].movieId | tostring else map(.episodeId | tostring) | unique | join(",") end)]
    | @tsv'
}

# Old files an import failed to delete (ImportApprovedMovie/ImportApprovedEpisodes).
failed_deletes() {
  api "log?page=1&pageSize=$log_page_size&sortKey=time&sortDirection=descending" | jq -r '
    [.records[]
      | select((.logger // "") | startswith("ImportApproved"))
      | (.exception // "") | capture("Read-only file system : \u0027(?<path>[^\u0027]+)\u0027") | .path]
    | unique[]'
}

unblock_upgrades() {
  local download_id ids path
  local -A waiting=()
  # Current files of the titles that still have a download waiting to import.
  while IFS=$'\t' read -r download_id ids; do
    while IFS= read -r path; do
      if [[ -n "$path" ]]; then
        waiting["$path"]=$download_id
      fi
    done < <(current_files "$ids")
  done < <(pending_downloads)

  while IFS= read -r path; do
    if [[ -n "${waiting["$path"]:-}" ]] && is_media_link "$path"; then
      echo "upgrade ${waiting["$path"]}: dropping $path"
      remove "$path"
    fi
  done < <(failed_deletes)
}

# True when the folder holds nothing but subfolders and links into the TorBox mount.
only_media_links() { # only_media_links <folder>
  local file
  while IFS= read -r -d '' file; do
    is_media_link "$file" || return 1
  done < <(find "$1" -mindepth 1 ! -type d -print0)
}

remove_orphans() {
  local resource known dir
  local orphans=()
  [[ "$app" == radarr ]] && resource=movie || resource=series
  known=$(api "$resource" | jq -r '.[].path')
  if [[ -z "$known" ]]; then
    echo "$app returned no $resource paths: orphan cleanup skipped" >&2
    return 1
  fi
  while IFS= read -r -d '' dir; do
    grep -qxF -- "$dir" <<<"$known" && continue
    if only_media_links "$dir"; then
      orphans+=("$dir")
    else
      echo "orphan $dir holds other files: left in place"
    fi
  done < <(find "$library_root" -mindepth 1 -maxdepth 1 -type d -mmin +"$orphan_min_age_minutes" -print0)

  if ((${#orphans[@]} > max_orphans)); then
    echo "${#orphans[@]} orphan folders (limit $max_orphans): check the paths, nothing removed" >&2
    return 1
  fi
  for dir in "${orphans[@]}"; do
    remove "$dir"
  done
}

unblock_upgrades
remove_orphans
