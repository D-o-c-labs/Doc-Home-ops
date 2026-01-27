#!/usr/bin/env bash
set -euo pipefail

file="${1:-}"
if [[ -z "$file" ]]; then
  echo "usage: $0 <file>" >&2
  exit 2
fi

diff="$(git diff -- "$file" || true)"
if [[ -z "$diff" ]]; then
  exit 0
fi

check_var() {
  local var="$1"
  local old new

  old="$(printf '%s\n' "$diff" | sed -n "s/^-\\s*${var}: v\\?\\([0-9][0-9.]*\\).*/\\1/p" | tail -n1)"
  new="$(printf '%s\n' "$diff" | sed -n "s/^+\\s*${var}: v\\?\\([0-9][0-9.]*\\).*/\\1/p" | tail -n1)"

  if [[ -z "$old" || -z "$new" ]]; then
    return 0
  fi

  IFS=. read -r old_major old_minor old_patch <<<"$old"
  IFS=. read -r new_major new_minor new_patch <<<"$new"

  old_major="${old_major:-0}"
  old_minor="${old_minor:-0}"
  new_major="${new_major:-0}"
  new_minor="${new_minor:-0}"

  if (( new_major > old_major + 1 )); then
    echo "rejecting ${var}: major jump ${old} -> ${new}" >&2
    return 1
  fi

  if (( new_major > old_major )); then
    if (( new_major == old_major + 1 && new_minor == 0 )); then
      return 0
    fi
    echo "rejecting ${var}: major upgrade must be next major with .0.x (${old} -> ${new})" >&2
    return 1
  fi

  if (( new_minor > old_minor + 1 )); then
    echo "rejecting ${var}: minor jump ${old} -> ${new}" >&2
    return 1
  fi

  if (( new_minor < old_minor )); then
    echo "rejecting ${var}: minor downgrade ${old} -> ${new}" >&2
    return 1
  fi
}

check_var "TALOS_VERSION"
check_var "KUBERNETES_VERSION"
