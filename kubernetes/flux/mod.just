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
  if [[ "$ns_args" == ns_flag=* ]]; then ns_args="${ns_args#ns_flag=}"; fi
  if [[ "$name_arg" == name=* ]]; then name_arg="${name_arg#name=}"; fi
  if [[ "$ns_args" == name=* && -z "$name_arg" ]]; then
    name_arg="${ns_args#name=}"
    ns_args="--all-namespaces"
  fi

  command -v yq >/dev/null || { echo 'yq not found in PATH' >&2; exit 1; }

  repo_root="{{ justfile_dir() }}"
  workspace_parent="$(dirname "$repo_root")"
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
    NAMESPACE="$namespace" yq e '.metadata.namespace = (.metadata.namespace // strenv(NAMESPACE)) | .spec.targetNamespace = (.spec.targetNamespace // strenv(NAMESPACE))' "$dir_path/ks.yaml" > "$tmp_dir/ks.yaml"
  else
    printf 'unable to locate Flux Kustomization manifest: %s\n' "$dir_path/ks.yaml" >&2
    exit 1
  fi

  source_repo_file="$dir_path/source/gitrepository.yaml"
  if [[ -f "$source_repo_file" ]]; then
    command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
    repo_name="$(yq e '.metadata.name // ""' "$source_repo_file")"
    repo_namespace="$(NAMESPACE="$namespace" yq e '.metadata.namespace // strenv(NAMESPACE)' "$source_repo_file")"
    repo_url="$(yq e '.spec.url // ""' "$source_repo_file")"
    repo_dir="$workspace_parent/$(basename "${repo_url%.git}")"
    repo_render_dir="$tmp_dir/source-$repo_name"
    if [[ -z "$repo_name" || -z "$repo_namespace" || -z "$repo_url" ]]; then
      printf 'unable to derive GitRepository metadata from %s\n' "$source_repo_file" >&2
      exit 1
    fi
    if [[ ! -d "$repo_dir/.git" ]]; then
      printf 'unable to locate local checkout for GitRepository/%s/%s at %s\n' "$repo_namespace" "$repo_name" "$repo_dir" >&2
      exit 1
    fi
    mkdir -p "$repo_render_dir"
    cp -R "$repo_dir"/. "$repo_render_dir"

    doc_max="$(yq e 'document_index' "$tmp_dir/ks.yaml" | tail -n1)"
    : > "$out_file"
    rendered=0

    for idx in $(seq 0 "$doc_max"); do
      doc_kind="$(yq e "select(document_index == $idx) | .kind // \"\"" "$tmp_dir/ks.yaml")"
      [[ "$doc_kind" == "Kustomization" ]] || continue

      doc_name="$(yq e "select(document_index == $idx) | .metadata.name // \"\"" "$tmp_dir/ks.yaml")"
      if [[ -n "$name_arg" && "$doc_name" != "$name_arg" ]]; then
        continue
      fi

      doc_file="$tmp_dir/ks-$idx.yaml"
      yq e "select(document_index == $idx)" "$tmp_dir/ks.yaml" > "$doc_file"

      doc_source_name="$(yq e '.spec.sourceRef.name // ""' "$doc_file")"
      doc_source_namespace="$(NAMESPACE="$namespace" yq e '.spec.sourceRef.namespace // strenv(NAMESPACE)' "$doc_file")"
      doc_path="$(yq e '.spec.path // "./"' "$doc_file")"
      doc_path="${doc_path#./}"

      if [[ "$doc_source_name" == "flux-system" && "$doc_source_namespace" == "flux-system" ]]; then
        build_path="$repo_root/${doc_path}"
      elif [[ "$doc_source_name" == "$repo_name" && "$doc_source_namespace" == "$repo_namespace" ]]; then
        build_path="$repo_render_dir/${doc_path}"
      else
        printf 'unable to map sourceRef %s/%s for %s\n' "$doc_source_namespace" "$doc_source_name" "$doc_name" >&2
        exit 1
      fi

      if [[ ! -d "$build_path" ]]; then
        printf 'unable to locate manifests path for %s: %s\n' "$doc_name" "$build_path" >&2
        exit 1
      fi

      flux_cmd=(flux build kustomization "$doc_name" --dry-run --namespace "$namespace" --path "$build_path" --kustomization-file "$doc_file")
      if [[ "$doc_source_name" == "$repo_name" && "$doc_source_namespace" == "$repo_namespace" ]]; then
        flux_cmd+=(--local-sources "GitRepository/${repo_namespace}/${repo_name}=$repo_render_dir")
      fi

      if [[ -s "$out_file" ]]; then
        printf '\n---\n' >> "$out_file"
      fi

      "${flux_cmd[@]}" >> "$out_file"
      rendered=1
    done

    [[ "$rendered" -eq 1 ]] || { printf 'no Kustomization matched in %s\n' "$tmp_dir/ks.yaml" >&2; exit 1; }
    cat "$out_file"
    exit 0
  fi

  command -v flux-local >/dev/null || { echo 'flux-local not found in PATH' >&2; exit 1; }

  cmd=(flux-local build ks)
  if [[ -n "$ns_args" ]]; then
    read -r -a ns_tokens <<< "$ns_args"
    cmd+=("${ns_tokens[@]}")
  fi
  cmd+=(--path "$tmp_dir")
  if [[ -n "$name_arg" ]]; then
    cmd+=("$name_arg")
  fi
  cmd+=(--output-file "$out_file")

  "${cmd[@]}"
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
