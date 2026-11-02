#!/usr/bin/env bash
# Radarr/Sonarr "Import Using Script" (Settings -> Media Management).
# Decypharr downloads are symlinks into its read-only NFS export. The built-in
# move first clears the read-only flag on the link target and fails with EROFS,
# so this moves or copies the link itself. Every other import goes back to the app.
set -euo pipefail

# Source and destination come as arguments. The apps build the environment with
# a StringDictionary, which lowercases the variable names.
source_path=${1:-}
destination_path=${2:-}
transfer_mode=${radarr_transfermode:-${sonarr_transfermode:-}}

# Only absolute links stay valid after being moved to another folder.
if [[ -z "$source_path" || -z "$destination_path" || ! -L "$source_path" || "$(readlink -- "$source_path")" != /* ]]; then
  echo "[MoveStatus] DeferMove"
  exit 0
fi

if [[ "$transfer_mode" == "Move" ]]; then
  mv -f -- "$source_path" "$destination_path"
else
  # Copy or HardLinkOrCopy: the download client still owns the source link.
  cp -P -f -- "$source_path" "$destination_path"
fi
echo "[MoveStatus] MoveComplete"
