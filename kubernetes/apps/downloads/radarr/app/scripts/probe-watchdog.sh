#!/usr/bin/env bash
# Kill ffprobe runs that hang on an unreadable file. Radarr probes every
# downloaded file on import; a file whose reads never return
# leaves ffprobe in uninterruptible sleep on the NFS mount, and the hung probe
# holds Radarr's import command, so no download imports until it ends.
# Runs as a sidecar sharing the app's process namespace: SIGKILL ends an NFS
# wait, then the queue item whose download holds the file is removed from the
# client, blocklisted and searched again. DRY_RUN=true logs instead.
set -euo pipefail

url=${ARR_URL:-http://localhost:7878}
max_probe_seconds=${MAX_PROBE_SECONDS:-300}
check_seconds=${CHECK_SECONDS:-30}
dry_run=${DRY_RUN:-false}
queue_page_size=${QUEUE_PAGE_SIZE:-2000}
clock_ticks=$(getconf CLK_TCK)

# The API key reaches curl on stdin, so it never shows up in the process list.
api() { # api <method> <endpoint>
  curl -fsS --max-time 60 -X "$1" -H @- "$url/api/v3/$2" <<<"X-Api-Key: ${ARR_API_KEY:?}"
}

# ffprobe processes older than max_probe_seconds: pid, age in seconds, probed file.
hung_probes() {
  local proc age uptime
  local -a stat_fields
  uptime=$(cut -d' ' -f1 /proc/uptime)
  for proc in /proc/[0-9]*; do
    [[ "$(cat "$proc/comm" 2>/dev/null)" == ffprobe ]] || continue
    # Field 22 of /proc/<pid>/stat is the start time in clock ticks; the
    # command name in field 2 has no spaces for ffprobe.
    read -ra stat_fields <"$proc/stat" 2>/dev/null || continue
    age=$((${uptime%.*} - stat_fields[21] / clock_ticks))
    ((age >= max_probe_seconds)) || continue
    printf '%s\t%s\t%s\n' "${proc#/proc/}" "$age" "$(tr '\0' '\n' <"$proc/cmdline" | tail -n 1)"
  done
}

# Queue item whose download path holds the file, if any: id, then title.
queue_item_for() { # queue_item_for <file>
  api GET "queue?pageSize=$queue_page_size" | jq -r --arg file "$1" '
    [.records[] | select(.outputPath != null)
      | .outputPath as $path | select($file == $path or ($file | startswith($path + "/")))]
    | first | select(. != null) | "\(.id)\t\(.title)"'
}

handle() { # handle <pid> <age> <file>
  local pid=$1 age=$2 file=$3 item
  if [[ "$dry_run" == true ]]; then
    echo "would kill ffprobe $pid (${age}s): $file"
    return 0
  fi
  kill -9 "$pid" 2>/dev/null || return 0
  echo "killed ffprobe $pid after ${age}s: $file"
  item=$(queue_item_for "$file")
  [[ -n "$item" ]] || return 0
  api DELETE "queue/${item%%$'\t'*}?removeFromClient=true&blocklist=true&skipRedownload=false" >/dev/null
  echo "blocklisted and searching again: ${item#*$'\t'}"
}

echo "watching ffprobe runs longer than ${max_probe_seconds}s"
while true; do
  while IFS=$'\t' read -r pid age file; do
    handle "$pid" "$age" "$file" || echo "failed to handle ffprobe $pid: $file" >&2
  done < <(hung_probes)
  sleep "$check_seconds"
done
