#!/usr/bin/env bash
# topf secrets provider: prints the Talos secrets bundle rendered from 1Password, so it never touches disk.
# https://postfinance.github.io/topf/main/providers/#secrets-provider
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-} ${2:-}" in
  "secrets get")
    # topf treats empty output as "no bundle" and offers to generate a new one, so fail instead.
    bundle="$(op run --env-file "$dir/secrets.env" --no-masking -- envsubst < "$dir/secrets.yaml.tpl")"
    grep -q 'key: [^$[:space:]]' <<< "$bundle" || { echo "secrets.sh: 1Password returned an empty bundle" >&2; exit 1; }
    printf '%s\n' "$bundle"
    ;;
  "secrets put")
    echo "secrets.sh: refusing to store a new bundle; the cluster secrets live in 1Password (automation/talos - home-ops)" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 secrets get|put <clusterName>" >&2
    exit 1
    ;;
esac
