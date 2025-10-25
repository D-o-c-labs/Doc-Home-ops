set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
apps_dir := kubernetes_dir + '/apps'

[private]
default:
  just -l flux

[private]
_render-ks dir ns_flag name:
  dir_path="{{ apps_dir }}/{{ dir }}"
  if [[ ! -d "$dir_path" ]]; then printf 'unable to locate Kustomization directory: %s\n' "$dir_path" >&2; exit 1; fi
  ns_args="{{ ns_flag }}"
  name_arg="{{ name }}"
  command -v flux-local >/dev/null || { echo 'flux-local not found in PATH' >&2; exit 1; }
  flux-local build ks ${ns_args:+$ns_args} --path "$dir_path" ${name_arg:+$name_arg}

[doc('Render a Flux Kustomization stack to stdout')]
build-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks dir="{{ dir }}" ns_flag="{{ ns_flag }}" name="{{ name }}" | yq -

[doc('Render and apply a Flux Kustomization stack')]
apply-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks dir="{{ dir }}" ns_flag="{{ ns_flag }}" name="{{ name }}" \
  | kubectl apply --server-side --field-manager=kustomize-controller -f -

[doc('Render and delete a Flux Kustomization stack')]
delete-ks dir ns_flag='--all-namespaces' name='':
  just flux _render-ks dir="{{ dir }}" ns_flag="{{ ns_flag }}" name="{{ name }}" \
  | kubectl delete -f -

[doc('Suspend all Flux Kustomizations, optionally scoped to specific namespaces')]
suspend-ks-all namespaces='':
  command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
  if [[ -n "{{ namespaces }}" ]]; then namespaces_input="{{ namespaces }}"; else namespaces_input="$(kubectl get ns --no-headers -o custom-columns='NAME:.metadata.name')"; fi
  for ns in $namespaces_input; do
  [[ -z "$ns" ]] && continue
  flux suspend ks -n "$ns" --all || true
  done

[doc('Resume all Flux Kustomizations, optionally scoped to specific namespaces')]
resume-ks-all namespaces='':
  command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
  if [[ -n "{{ namespaces }}" ]]; then namespaces_input="{{ namespaces }}"; else namespaces_input="$(kubectl get ns --no-headers -o custom-columns='NAME:.metadata.name')"; fi
  for ns in $namespaces_input; do
  [[ -z "$ns" ]] && continue
  flux resume ks -n "$ns" --all || true
  done
