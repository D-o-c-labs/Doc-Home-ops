set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Decrypt and re-encrypt every SOPS managed secret in-place')]
re-encrypt:
  command -v sops >/dev/null || { echo 'sops binary not found' >&2; exit 1; }
  find . -type f -name '*.sops.yaml' ! -name '.sops.yaml' -print0 \
  | while IFS= read -r -d '' secret; do
  sops --decrypt --in-place "$secret"
  sops --encrypt --in-place "$secret"
  done
