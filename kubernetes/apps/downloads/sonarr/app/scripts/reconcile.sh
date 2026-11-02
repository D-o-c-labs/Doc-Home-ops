#!/usr/bin/env bash
# Clean up after Radarr/Sonarr on the external library. Both clear the read-only
# flag of a file before deleting it; on a Decypharr symlink that follows the link
# to the read-only TorBox mount and fails with EROFS, so:
# - an upgrade stays blocked in the queue because the old file cannot be deleted.
#   Once the app accepts the new file, drop the old link: the next import retry
#   skips the delete and moves the new link with import.sh;
# - a deleted title leaves its folder behind. Remove folders the app no longer
#   knows that hold only links into the TorBox mount.
# Only links into the TorBox mount are ever removed. DRY_RUN=true logs instead.
set -euo pipefail

app=${ARR_APP:?ARR_APP must be radarr or sonarr}
url=${ARR_URL:?}
library_root=${LIBRARY_ROOT:?}
media_root=${MEDIA_ROOT:-/data/external-media}
dry_run=${DRY_RUN:-false}
queue_page_size=${QUEUE_PAGE_SIZE:-2000}
# Skip folders changed recently: an import creates the folder before the title record.
orphan_min_age_minutes=${ORPHAN_MIN_AGE_MINUTES:-60}
# More orphans than this in one run points at a path mismatch, not at deletions.
max_orphans=${MAX_ORPHANS:-50}

api() { curl -fsS --max-time 300 -H "X-Api-Key: ${ARR_API_KEY:?}" "$url/api/v3/$1"; }

is_media_link() { [[ -L "$1" && "$(readlink -- "$1")" == "$media_root"/* ]]; }

remove() {
  if [[ "$dry_run" == true ]]; then
    echo "would remove $1"
  else
    rm -rf -- "$1"
    echo "removed $1"
  fi
}

# Library files that importing this manual import item would replace.
replaced_files() { # replaced_files <manual import item as JSON>
  local item=$1 id
  if [[ "$app" == radarr ]]; then
    id=$(jq -r '.movie.id // empty' <<<"$item")
    if [[ -n "$id" ]]; then
      api "moviefile?movieId=$id" | jq -r '.[].path'
    fi
  else
    for id in $(jq -r '[.episodes[]?.episodeFileId | select(. > 0)] | unique[]' <<<"$item"); do
      api "episodefile/$id" | jq -r '.path'
    done
  fi
}

unblock_upgrades() {
  local download_id item new_path old_path
  # Sonarr lists one queue record per episode: handle each download once.
  for download_id in $(api "queue?pageSize=$queue_page_size" | jq -r '
    [.records[] | select(.status == "completed" and .trackedDownloadState == "importBlocked") | .downloadId]
    | unique[]'); do
    # No rejections: the app would import the file, only deleting the old one fails.
    while IFS= read -r item; do
      new_path=$(jq -r '.path' <<<"$item")
      is_media_link "$new_path" || continue
      while IFS= read -r old_path; do
        if [[ -n "$old_path" ]] && is_media_link "$old_path"; then
          echo "upgrade $download_id: dropping $old_path for $new_path"
          remove "$old_path"
        fi
      done < <(replaced_files "$item")
    done < <(api "manualimport?downloadId=$download_id&filterExistingFiles=true" |
      jq -c '.[] | select((.rejections // []) | length == 0)')
  done
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
