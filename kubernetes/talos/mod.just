set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
talos_dir := kubernetes_dir + '/talos'
clusterconfig_dir := talos_dir + '/clusterconfig'

[private]
default:
  just -l talos

[doc('Generate Talos cluster configuration manifests using talhelper')]
generate-clusterconfig:
  command -v talhelper >/dev/null || { echo 'talhelper CLI is required' >&2; exit 1; }
  command -v op >/dev/null || { echo '1Password CLI (op) is required' >&2; exit 1; }
  test -f "{{ talos_dir }}/talsecret.yaml"
  test -f "{{ talos_dir }}/talconfig.yaml"
  test -f "{{ talos_dir }}/talhelper-secrets.env"
  op run --env-file "{{ talos_dir }}/talhelper-secrets.env" --no-masking -- talhelper genconfig \
  --secret-file "{{ talos_dir }}/talsecret.yaml" \
  --config-file "{{ talos_dir }}/talconfig.yaml" \
  --out-dir "{{ clusterconfig_dir }}"

[doc('Apply talhelper-generated Talos machineconfigs to every node')]
apply-clusterconfig mode='auto' dry_run='false' insecure='false':
  command -v talosctl >/dev/null || { echo 'talosctl CLI is required' >&2; exit 1; }
  test -d "{{ clusterconfig_dir }}"
  shopt -s nullglob
  files=("{{ clusterconfig_dir }}"/*.yaml)
  if [[ ${#files[@]} -eq 0 ]]; then echo 'no clusterconfig YAML files found to apply' >&2; exit 1; fi
  for file in "${files[@]}"; do
  base=$(basename "$file")
  hostname=${base%.yaml}
  hostname=${hostname#doc-home-ops-}
  just talos _apply-machineconfig path="$file" hostname="$hostname" mode="{{ mode }}" dry_run="{{ dry_run }}" insecure="{{ insecure }}"
  done
  shopt -u nullglob

[doc('Apply Talos config to a node')]
apply-node node *args:
  just talos render-config "{{ node }}" | talosctl -n "{{ node }}" apply-config -f /dev/stdin {{ args }}

[doc('Apply Talos config to all nodes in the cluster')]
apply-cluster *args:
  kubectl get nodes --no-headers | while read -r node _; do \
    just log info "Applying Talos config to node ${node}"; \
    just talos apply-node ${node} {{ args }}; \
  done

[doc('Generate kubeconfig for Talos cluster')]
gen-kubeconfig:
  controller=$(talosctl config info --output json | jq --raw-output '.endpoints[]' | shuf -n 1)
  talosctl kubeconfig -n "$controller" -f --force-context-name main {{ kubernetes_dir }}

[doc('Generate schematic ID from Talos schematic')]
gen-schematic-id:
  curl -sX POST --data-binary "@{{ talos_dir }}/schematic.yaml" "https://factory.talos.dev/schematics" | jq -r '.id'

[doc('Render Talos config for a node')]
render-config node:
  export IS_CONTROLPLANE="$(just talos machine-controller {{ node }})"; \
  talosctl machineconfig patch <(just template "{{ talos_dir }}/machineconfig.yaml.j2") \
    -p @<(just template "{{ talos_dir }}/nodes/{{ node }}.yaml.j2")

[doc('Reboot a node')]
reboot-node node:
  gum confirm "Reboot node {{ node }}?" && \
    talosctl -n {{ node }} reboot -m powercycle || exit 0

[doc('Reset a node')]
reset-node node mode="reboot":
  gum confirm "Reset node {{ node }}?" && \
    talosctl -n "{{ node }}" reset --graceful=false {{ if mode == "reboot" { "--reboot" } else { "" } }} || exit 0

[doc('Reset all nodes in the cluster')]
reset-cluster mode="reboot":
  kubectl get nodes --no-headers | while read -r node _; do \
    just log info "Resetting Talos node ${node}";\
    just talos reset-node ${node} {{ mode }};\
  done

[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
  controller=$(talosctl config info --output json | jq --raw-output '.endpoints[]' | shuf -n 1)
  talosctl -n "$controller" upgrade-k8s --to {{ version }}

[doc('Upgrade Talos version on a node')]
upgrade-node node:
  talosctl -n "{{ node }}" upgrade -i "$(just talos machine-image {{ node }})" -m powercycle --timeout=10m

[doc('Download Talos machine image')]
download-image version schematic:
  gum spin --title "Downloading Talos {{ version }} ..." -- \
  curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
      -o "{{ talos_dir }}/talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
      "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
  just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

[private]
_apply-machineconfig path hostname mode='auto' dry_run='false' insecure='false':
  args=(--nodes "{{ hostname }}" --file "{{ path }}" --mode "{{ mode }}")
  if [[ "{{ dry_run }}" == "true" ]]; then args+=(--dry-run); fi
  if [[ "{{ insecure }}" == "true" ]]; then args+=(--insecure); fi
  talosctl apply-config "${args[@]}"

[private]
machine-controller node:
  just template "{{ talos_dir }}/nodes/{{ node }}.yaml.j2" | yq -e 'select(.machine) | (.machine.type == "controlplane") // ""'

[doc('Get the machine image for a given node')]
[private]
machine-image node:
  talosctl --nodes {{ node }} get machineconfig --output=jsonpath='{.spec}' | yq -e 'select(.machine) | .machine.install.image'
