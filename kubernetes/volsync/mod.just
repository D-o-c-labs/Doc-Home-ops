set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
volsync_dir := kubernetes_dir + '/volsync'
templates_dir := volsync_dir + '/templates'

[private]
default:
  just -l volsync

[doc('Unlock all VolSync replication sources across the cluster')]
unlock:
  command -v kubectl >/dev/null || { echo 'kubectl not found in PATH' >&2; exit 1; }
  sources=$(kubectl get replicationsources --all-namespaces --no-headers --output=jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name}{"\n"}{end}') || { echo 'failed to list VolSync replication sources' >&2; exit 1; }
  if [[ -z "${sources:-}" ]]; then echo 'no VolSync replication sources found to unlock'; exit 0; fi
  while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  ns="${entry%%,*}"
  name="${entry##*,}"
  kubectl --namespace "$ns" patch --field-manager=flux-client-side-apply replicationsources "$name" --type merge --patch "{\"spec\":{\"restic\":{\"unlock\":\"$(date +%s)\"}}}" || true
  done <<< "${sources:-}"

[doc('List VolSync snapshots for an application')]
list app ns='default':
  command -v minijinja-cli >/dev/null || { echo 'minijinja-cli is required' >&2; exit 1; }
  command -v stern >/dev/null || { echo 'stern CLI is required' >&2; exit 1; }
  job="list-snapshots-${app}"
  kubectl --namespace "{{ ns }}" get replicationsources "{{ app }}-wasabi"
  NS="{{ ns }}" APP="{{ app }}" minijinja-cli "{{ templates_dir }}/list-snapshots.yaml.j2" | kubectl apply --server-side --filename -
  until kubectl --namespace "{{ ns }}" get job/"${job}" &>/dev/null; do sleep 5; done
  kubectl --namespace "{{ ns }}" wait job/"${job}" --for=condition=complete --timeout=5m
  stern --namespace "{{ ns }}" job/"${job}" --no-follow
  kubectl --namespace "{{ ns }}" delete job "${job}"

[doc('Trigger a VolSync snapshot for an application')]
snapshot app ns='default' wait='true':
  kubectl --namespace "{{ ns }}" get replicationsources "{{ app }}-wasabi"
  kubectl --namespace "{{ ns }}" patch replicationsources "{{ app }}-wasabi" --type merge -p '{"spec":{"trigger":{"manual":"'"$(date +%s)"'"}}}'
  if [[ "{{ wait }}" == "true" ]]; then job="volsync-src-{{ app }}"; until kubectl --namespace "{{ ns }}" get job/"${job}" &>/dev/null; do sleep 5; done; kubectl --namespace "{{ ns }}" wait job/"${job}" --for=condition=complete --timeout=120m; fi

[doc('Trigger VolSync snapshots for every application without waiting')]
snapshot-all:
  raw_apps=$(kubectl get replicationsources -A --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name}{"\n"}{end}') || { echo 'failed to list VolSync replication sources' >&2; exit 1; }
  if [[ -z "${raw_apps:-}" ]]; then echo 'no VolSync replication sources found to snapshot'; exit 0; fi
  while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  [[ "$entry" == *'-r2' ]] && continue
  ns="${entry%%,*}"
  app="${entry##*,}"
  just volsync snapshot "${app}" ns="$ns" wait='false'
  done <<< "${raw_apps:-}"

[doc('Restore a VolSync snapshot for an application')]
restore app previous ns='default':
  command -v minijinja-cli >/dev/null || { echo 'minijinja-cli is required' >&2; exit 1; }
  command -v flux >/dev/null || { echo 'flux CLI not found in PATH' >&2; exit 1; }
  controller=$(kubectl --namespace "{{ ns }}" get deployment "{{ app }}" &>/dev/null && echo deployment || echo statefulset)
  claim=$(kubectl --namespace "{{ ns }}" get replicationsources/{{ app }}-wasabi --output=jsonpath='{.spec.sourcePVC}')
  access_modes=$(kubectl --namespace "{{ ns }}" get replicationsources/{{ app }}-wasabi --output=jsonpath='{.spec.restic.accessModes}')
  storage_class=$(kubectl --namespace "{{ ns }}" get replicationsources/{{ app }}-wasabi --output=jsonpath='{.spec.restic.storageClassName}')
  puid=$(kubectl --namespace "{{ ns }}" get replicationsources/{{ app }}-wasabi --output=jsonpath='{.spec.restic.moverSecurityContext.runAsUser}')
  pgid=$(kubectl --namespace "{{ ns }}" get replicationsources/{{ app }}-wasabi --output=jsonpath='{.spec.restic.moverSecurityContext.runAsGroup}')
  flux --namespace flux-system suspend kustomization "{{ app }}"
  flux --namespace "{{ ns }}" suspend helmrelease "{{ app }}"
  kubectl --namespace "{{ ns }}" scale ${controller}/"{{ app }}" --replicas 0
  kubectl --namespace "{{ ns }}" wait pod --for=delete --selector="app.kubernetes.io/name={{ app }}" --timeout=5m
  NS="{{ ns }}" APP="{{ app }}" PREVIOUS="{{ previous }}" CLAIM="$claim" ACCESS_MODES="$access_modes" STORAGE_CLASS_NAME="$storage_class" PUID="$puid" PGID="$pgid" \
  minijinja-cli "{{ templates_dir }}/replicationdestination.yaml.j2" | kubectl apply --server-side --filename -
  until kubectl --namespace "{{ ns }}" get job/volsync-dst-{{ app }}-manual &>/dev/null; do sleep 5; done
  kubectl --namespace "{{ ns }}" wait job/volsync-dst-{{ app }}-manual --for=condition=complete --timeout=120m
  kubectl --namespace "{{ ns }}" delete replicationdestination "{{ app }}"-manual
  flux --namespace flux-system resume kustomization "{{ app }}"
  flux --namespace "{{ ns }}" resume helmrelease "{{ app }}"
  flux --namespace "{{ ns }}" reconcile helmrelease "{{ app }}" --force
  kubectl --namespace "{{ ns }}" wait pod --for=condition=ready --selector="app.kubernetes.io/name={{ app }}" --timeout=5m
