set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
apps_dir := kubernetes_dir + '/apps'

[private]
default:
  just -l flux

[private]
_render-ks dir ns_flag name:
  #!/usr/bin/env bash
  set -euo pipefail

  apps_dir="{{ apps_dir }}"
  dir="{{ dir }}"
  dir="${dir#dir=}"
  dir_path="$apps_dir/$dir"
  if [[ ! -d "$dir_path" ]]; then printf 'unable to locate Kustomization directory: %s\n' "$dir_path" >&2; exit 1; fi

  namespace="${dir%%/*}"
  ns_args="{{ ns_flag }}"
  name_arg="{{ name }}"

  command -v flux-local >/dev/null || { echo 'flux-local not found in PATH' >&2; exit 1; }
  command -v yq >/dev/null || { echo 'yq not found in PATH' >&2; exit 1; }

  tmp_root="{{ kubernetes_dir }}/.tmp/flux-local"
  mkdir -p "$tmp_root"
  tmp_dir="$(mktemp -d -p "$tmp_root")"
  out_file="$tmp_dir/out.yaml"
  cleanup() {
    rm -rf "$tmp_dir"
    rmdir "$tmp_root" 2>/dev/null || true
    rmdir "{{ kubernetes_dir }}/.tmp" 2>/dev/null || true
  }
  trap cleanup EXIT

  if [[ -f "$dir_path/ks.yaml" ]]; then
    NAMESPACE="$namespace" yq e '.metadata.namespace = (.metadata.namespace // strenv(NAMESPACE))' "$dir_path/ks.yaml" > "$tmp_dir/ks.yaml"
  else
    printf 'unable to locate Flux Kustomization manifest: %s\n' "$dir_path/ks.yaml" >&2
    exit 1
  fi

  flux-local build ks ${ns_args:+$ns_args} --path "$tmp_dir" ${name_arg:+$name_arg} --output-file "$out_file"
  cat "$out_file"

[doc('Render a Flux Kustomization stack to stdout')]
build-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks "{{ dir }}" "{{ ns_flag }}" "{{ name }}" | yq -

[doc('Render and apply a Flux Kustomization stack')]
apply-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks "{{ dir }}" "{{ ns_flag }}" "{{ name }}" \
  | kubectl apply --server-side --field-manager=kustomize-controller -f -

[doc('Render and delete a Flux Kustomization stack')]
delete-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks "{{ dir }}" "{{ ns_flag }}" "{{ name }}" \
  | kubectl delete -f -

[doc('Suspend all Flux Kustomizations, optionally scoped to specific namespaces')]
suspend-ks-all namespaces='':
  #!/usr/bin/env bash
  set -euo pipefail

  command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
  if [[ -n "{{ namespaces }}" ]]; then namespaces_input="{{ namespaces }}"; else namespaces_input="$(kubectl get ns --no-headers -o custom-columns='NAME:.metadata.name')"; fi
  for ns in $namespaces_input; do
    [[ -z "$ns" ]] && continue
    flux suspend ks -n "$ns" --all || true
  done

[doc('Resume all Flux Kustomizations, optionally scoped to specific namespaces')]
resume-ks-all namespaces='':
  #!/usr/bin/env bash
  set -euo pipefail

  command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
  if [[ -n "{{ namespaces }}" ]]; then namespaces_input="{{ namespaces }}"; else namespaces_input="$(kubectl get ns --no-headers -o custom-columns='NAME:.metadata.name')"; fi
  for ns in $namespaces_input; do
    [[ -z "$ns" ]] && continue
    flux resume ks -n "$ns" --all || true
  done
