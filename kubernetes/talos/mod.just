
set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
talos_dir := kubernetes_dir + '/talos'

# Recipes run from kubernetes/talos, where topf finds topf.yaml and runs the ./secrets.sh provider.
# topf dials each node's IP directly and authenticates with a client cert minted from the 1Password bundle.

[private]
default:
  just -l talos

[doc('Render the machine configs to kubernetes/talos/rendered (plaintext secrets, delete after use)')]
render:
  topf render --output ./rendered

[doc('Show the pending config changes against the running nodes without applying them')]
diff:
  topf apply --dry-run || [[ $? -eq 2 ]]

[doc('Apply the Talos config to every node, one at a time (shows a diff and asks first)')]
apply mode="auto":
  topf apply --mode "{{ mode }}"

[doc('Apply the Talos config to one node, e.g. `just talos apply-node zeus` (shows a diff and asks first)')]
apply-node node mode="auto":
  just talos _node-host "{{ node }}" >/dev/null
  topf apply --nodes-filter "^{{ node }}(\.|$)" --mode "{{ mode }}"

[doc('List the nodes with their Talos version, schematic and stage')]
nodes:
  topf nodes

[doc('Print the schematic ID of each node from schematic.yaml')]
schematic-ids:
  topf schematic-ids

[doc('Generate kubernetes/talos/talosconfig from the secrets bundle')]
talosconfig:
  topf talosconfig > talosconfig

[doc('Generate kubeconfig for Talos cluster')]
gen-kubeconfig:
  controller=$(talosctl config info --output json | jq --raw-output '.endpoints[]' | shuf -n 1)
  talosctl kubeconfig -n "$controller" -f --force-context-name main {{ kubernetes_dir }}

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

[doc('Defragment etcd members sequentially with the current leader last')]
defrag-etcd *nodes:
  #!/usr/bin/env bash
  set -euo pipefail

  for command_name in talosctl jq awk gum; do
    command -v "$command_name" >/dev/null || {
      echo "$command_name CLI is required" >&2
      exit 1
    }
  done

  cluster_nodes=()
  while IFS= read -r node; do
    [[ -n "$node" ]] && cluster_nodes+=("$node")
  done < <(talosctl config info --output json | jq -er '.nodes[]')
  if [[ ${#cluster_nodes[@]} -eq 0 ]]; then
    echo 'the active Talos context contains no nodes' >&2
    exit 1
  fi

  requested_nodes=()
  for node in {{ nodes }}; do
    if [[ -z "$node" || "$node" == -* ]]; then
      echo "invalid node argument: $node" >&2
      exit 1
    fi
    requested_nodes+=("$node")
  done
  if [[ ${#requested_nodes[@]} -eq 0 ]]; then
    requested_nodes=("${cluster_nodes[@]}")
  fi

  join_by_comma() {
    local IFS=,
    echo "$*"
  }

  validate_status() {
    local table="$1"
    local expected="$2"
    awk -v expected="$expected" '
      NR == 1 {
        if ($1 != "NODE" || $2 != "MEMBER") exit 1
        next
      }
      NF < 13 { exit 1 }
      {
        count++
        if ($12 != "false") exit 1
        if (count == 1) {
          leader = $8
          term = $10
          min_applied = $11
          max_applied = $11
        }
        if ($8 != leader || $10 != term) exit 1
        if ($11 < min_applied) min_applied = $11
        if ($11 > max_applied) max_applied = $11
        if ($2 == $8) leader_rows++
        members[$2]++
      }
      END {
        if (count != expected || leader_rows != 1) exit 1
        if ((max_applied - min_applied) > 1000) exit 1
        for (member in members) if (members[member] != 1) exit 1
      }
    ' <<< "$table"
  }

  cluster_csv=$(join_by_comma "${cluster_nodes[@]}")
  initial_status=$(talosctl --nodes "$cluster_csv" etcd status)
  validate_status "$initial_status" "${#cluster_nodes[@]}" || {
    echo 'unable to validate cluster-wide etcd status' >&2
    exit 1
  }

  target_nodes=()
  target_members=()
  for requested in "${requested_nodes[@]}"; do
    single_status=$(talosctl --nodes "$requested" etcd status)
    mapping=$(awk '
      NR == 1 { next }
      NF < 13 { exit 1 }
      { rows++; node = $1; member = $2 }
      END {
        if (rows != 1) exit 1
        print node "\t" member
      }
    ' <<< "$single_status") || {
      echo "unable to map node to one etcd member: $requested" >&2
      exit 1
    }
    canonical_node=${mapping%%$'\t'*}
    member_id=${mapping#*$'\t'}
    member_matches=$(awk -v member="$member_id" 'NR > 1 && $2 == member { count++ } END { print count + 0 }' <<< "$initial_status")
    if [[ "$member_matches" != '1' ]]; then
      echo "target does not map to exactly one cluster member: $requested" >&2
      exit 1
    fi
    for existing_member in "${target_members[@]:-}"; do
      if [[ "$existing_member" == "$member_id" ]]; then
        echo "duplicate etcd member target: $requested" >&2
        exit 1
      fi
    done
    target_nodes+=("$canonical_node")
    target_members+=("$member_id")
  done

  printf '%s\n' "$initial_status"
  gum confirm "Defragment ${#target_nodes[@]} etcd member(s) sequentially?" || exit 0

  while [[ ${#target_nodes[@]} -gt 0 ]]; do
    current_status=$(talosctl --nodes "$cluster_csv" etcd status)
    validate_status "$current_status" "${#cluster_nodes[@]}" || {
      echo 'cluster-wide etcd status failed validation before defrag' >&2
      exit 1
    }
    leader_id=$(awk 'NR == 2 { print $8 }' <<< "$current_status")

    ordered_nodes=()
    ordered_members=()
    leader_node=''
    leader_member=''
    for index in "${!target_nodes[@]}"; do
      if [[ "${target_members[$index]}" == "$leader_id" ]]; then
        leader_node=${target_nodes[$index]}
        leader_member=${target_members[$index]}
      else
        ordered_nodes+=("${target_nodes[$index]}")
        ordered_members+=("${target_members[$index]}")
      fi
    done
    if [[ -n "$leader_node" ]]; then
      ordered_nodes+=("$leader_node")
      ordered_members+=("$leader_member")
    fi

    target_node=${ordered_nodes[0]}
    echo "Defragmenting etcd member on $target_node"
    talosctl --nodes "$target_node" etcd defrag

    post_status=$(talosctl --nodes "$cluster_csv" etcd status)
    validate_status "$post_status" "${#cluster_nodes[@]}" || {
      echo "etcd status failed validation after defragmenting $target_node" >&2
      exit 1
    }
    printf '%s\n' "$post_status"

    target_nodes=("${ordered_nodes[@]:1}")
    target_members=("${ordered_members[@]:1}")
  done

[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
  controller=$(talosctl config info --output json | jq --raw-output '.endpoints[]' | shuf -n 1)
  talosctl -n "$controller" upgrade-k8s --to {{ version }}

# tuppr drives Talos upgrades in-cluster; this is the manual fallback with the installer from topf.yaml
[doc('Upgrade Talos on one node, e.g. `just talos upgrade-node zeus`')]
upgrade-node node:
  just talos _node-host "{{ node }}" >/dev/null
  topf upgrade --nodes-filter "^{{ node }}(\.|$)" --reboot-mode powercycle --drain-timeout 15m

[doc('Download Talos machine image')]
download-image version schematic:
  gum spin --title "Downloading Talos {{ version }} ..." -- \
  curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
      -o "{{ talos_dir }}/talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
      "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
  just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

# topf's --nodes-filter matches nothing silently on a typo; fail instead
[private]
_node-host node:
  yq -e '.nodes[] | select(.host | test("^{{ node }}(\\.|$)")) | .host' topf.yaml
