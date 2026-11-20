#!/usr/bin/env bash
# Radarr/Sonarr "Import Using Script" (Settings -> Media Management).
# Two read-only sources import as links instead of going through the app:
# - Downloads from the external media VM are symlinks into its read-only NFS
#   export. The built-in move first clears the read-only flag on the link target and fails with EROFS,
#   so this moves or copies the link itself.
# - Files under the remote download folder are linked into the library: the
#   client keeps them in place, so a copy would only duplicate them.
# Every other import goes back to the app.
set -euo pipefail

# Source and destination come as arguments. The apps build the environment with
# a StringDictionary, which lowercases the variable names.
source_path=${1:-}
destination_path=${2:-}
transfer_mode=${radarr_transfermode:-${sonarr_transfermode:-}}
remote_root=${REMOTE_ROOT:-/data/remote-library}

if [[ -z "$source_path" || -z "$destination_path" ]]; then
  echo "[MoveStatus] DeferMove"
  exit 0
fi

if [[ "$source_path" == "$remote_root"/* && -f "$source_path" && ! -L "$source_path" ]]; then
  ln -s -f -- "$source_path" "$destination_path"
  echo "[MoveStatus] MoveComplete"
  exit 0
fi

# Only absolute links stay valid after being moved to another folder.
if [[ ! -L "$source_path" || "$(readlink -- "$source_path")" != /* ]]; then
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
