set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

default_ns := 'database'
default_cluster := 'postgres'
default_cli_args := '--verbose --format=c --no-comments --clean --if-exists --no-owner --extension plpgsql'
pgadmin_selector := 'postgres-operator.crunchydata.com/pgadmin=pgadmin'
pgadmin_port := '5050'

[private]
default:
  just -l postgres

[private]
_pgadmin-statefulset ns=default_ns:
  #!/usr/bin/env bash
  set -euo pipefail
  statefulsets=()
  while IFS= read -r statefulset; do
    [[ -n "$statefulset" ]] && statefulsets+=("$statefulset")
  done < <(kubectl get statefulsets.apps --namespace "{{ ns }}" --selector "{{ pgadmin_selector }}" --output name)
  if (( ${#statefulsets[@]} != 1 )); then
    printf 'expected exactly one PGAdmin StatefulSet in namespace %s, found %d\n' \
      "{{ ns }}" "${#statefulsets[@]}" >&2
    exit 1
  fi
  printf '%s\n' "${statefulsets[0]}"

[private]
_pgadmin-wait-down ns=default_ns timeout='5m':
  #!/usr/bin/env bash
  set -euo pipefail
  kubectl wait --namespace "{{ ns }}" --for=delete pod \
    --selector "{{ pgadmin_selector }}" --timeout="{{ timeout }}"

[doc('Scale PGAdmin up and wait until it is ready')]
pgadmin-up ns=default_ns timeout='5m':
  #!/usr/bin/env bash
  set -euo pipefail
  statefulset="$(just postgres _pgadmin-statefulset "{{ ns }}")"
  desired_replicas="$(kubectl get --namespace "{{ ns }}" "$statefulset" --output jsonpath='{.spec.replicas}')"
  if [[ "${desired_replicas:-1}" == "0" ]]; then
    just postgres _pgadmin-wait-down "{{ ns }}" "{{ timeout }}"
  fi
  kubectl scale --namespace "{{ ns }}" "$statefulset" --replicas=1
  kubectl rollout status --namespace "{{ ns }}" "$statefulset" --timeout="{{ timeout }}"
  pod="${statefulset#*/}-0"
  kubectl wait --namespace "{{ ns }}" --for=condition=Ready "pod/$pod" --timeout="{{ timeout }}"

[doc('Scale PGAdmin down and wait for its pod to terminate')]
pgadmin-down ns=default_ns timeout='5m':
  #!/usr/bin/env bash
  set -euo pipefail
  statefulset="$(just postgres _pgadmin-statefulset "{{ ns }}")"
  kubectl scale --namespace "{{ ns }}" "$statefulset" --replicas=0
  just postgres _pgadmin-wait-down "{{ ns }}" "{{ timeout }}"

[doc('Run an on-demand local PGAdmin session and scale it down on exit')]
pgadmin local_port=pgadmin_port ns=default_ns timeout='5m':
  #!/usr/bin/env bash
  set -euo pipefail
  statefulset="$(just postgres _pgadmin-statefulset "{{ ns }}")"
  port_forward_pid=''
  cleanup() {
    status=$?
    trap - EXIT
    trap '' HUP INT TERM
    if [[ -n "$port_forward_pid" ]]; then
      kill "$port_forward_pid" 2>/dev/null || true
      wait "$port_forward_pid" 2>/dev/null || true
      port_forward_pid=''
    fi
    printf '\nScaling PGAdmin down...\n'
    cleanup_failed=0
    kubectl scale --request-timeout=30s --namespace "{{ ns }}" \
      "$statefulset" --replicas=0 || cleanup_failed=1
    just postgres _pgadmin-wait-down "{{ ns }}" "{{ timeout }}" || cleanup_failed=1
    if (( cleanup_failed != 0 )); then
      printf 'failed to scale PGAdmin down; run just postgres pgadmin-down\n' >&2
      if (( status == 0 )); then
        status=1
      fi
    fi
    exit "$status"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  desired_replicas="$(kubectl get --namespace "{{ ns }}" "$statefulset" --output jsonpath='{.spec.replicas}')"
  if [[ "${desired_replicas:-1}" == "0" ]]; then
    just postgres _pgadmin-wait-down "{{ ns }}" "{{ timeout }}"
  fi
  kubectl scale --namespace "{{ ns }}" "$statefulset" --replicas=1
  kubectl rollout status --namespace "{{ ns }}" "$statefulset" --timeout="{{ timeout }}"
  pod="${statefulset#*/}-0"
  kubectl wait --namespace "{{ ns }}" --for=condition=Ready "pod/$pod" --timeout="{{ timeout }}"
  printf 'PGAdmin is available at http://127.0.0.1:%s (press Ctrl-C to stop)\n' "{{ local_port }}"
  kubectl port-forward --namespace "{{ ns }}" --address=127.0.0.1 \
    "pod/$pod" "{{ local_port }}:{{ pgadmin_port }}" &
  port_forward_pid=$!
  forward_status=0
  wait "$port_forward_pid" || forward_status=$?
  port_forward_pid=''
  exit "$forward_status"

[private]
_crunchy-primary ns=default_ns db_cluster=default_cluster:
  #!/usr/bin/env bash
  set -euo pipefail
  primary="$(kubectl get pods --namespace "{{ ns }}" \
    --selector "postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster={{ db_cluster }}" \
    --output jsonpath='{.items[0].metadata.name}')"
  if [[ -z "$primary" ]]; then
    printf 'no primary pod found for cluster %s in namespace %s\n' "{{ db_cluster }}" "{{ ns }}" >&2
    exit 1
  fi
  printf '%s\n' "$primary"

[doc('Run pg_dump on the master instance of a CrunchyData Postgres cluster')]
crunchy-dump db_name output_dir='.' ns=default_ns db_cluster=default_cluster cli_args=default_cli_args:
  #!/usr/bin/env bash
  set -euo pipefail
  primary="$(just postgres _crunchy-primary "{{ ns }}" "{{ db_cluster }}")"
  remote="/pgdata/{{ db_name }}.psql"
  trap 'kubectl exec --container database --namespace "{{ ns }}" "$primary" -- rm -f "$remote"' EXIT
  kubectl exec --container database --namespace "{{ ns }}" "$primary" -- \
    pg_dump --dbname "{{ db_name }}" {{ cli_args }} --file "$remote"
  kubectl cp --container database "{{ ns }}/$primary:$remote" "{{ output_dir }}/{{ db_name }}.psql"
  chmod 600 "{{ output_dir }}/{{ db_name }}.psql"

[doc('Restore a pg_dump backup into a CrunchyData Postgres cluster')]
crunchy-restore db_name db_user file ns=default_ns db_cluster=default_cluster cli_args='':
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ ! -f "{{ file }}" ]]; then printf 'backup file not found: %s\n' "{{ file }}" >&2; exit 1; fi
  primary="$(just postgres _crunchy-primary "{{ ns }}" "{{ db_cluster }}")"
  restore_flags="{{ cli_args }}"
  if [[ -z "$restore_flags" ]]; then
    restore_flags="--verbose --format=c --clean --if-exists --no-owner --role {{ db_user }}"
  fi
  remote="/pgdata/restore-{{ db_name }}.psql"
  trap 'kubectl exec --container database --namespace "{{ ns }}" "$primary" -- rm -f "$remote"' EXIT
  kubectl cp --container database "{{ file }}" "{{ ns }}/$primary:$remote"
  kubectl exec --container database --namespace "{{ ns }}" "$primary" -- \
    psql --command 'ALTER DATABASE "{{ db_name }}" OWNER TO "{{ db_user }}";'
  # shellcheck disable=SC2086 # restore_flags is a flag list
  kubectl exec --container database --namespace "{{ ns }}" "$primary" -- \
    pg_restore --dbname "{{ db_name }}" $restore_flags "$remote"

[doc('Open a shell inside the CrunchyData master pod')]
crunchy-exec ns=default_ns db_cluster=default_cluster:
  #!/usr/bin/env bash
  set -euo pipefail
  primary="$(just postgres _crunchy-primary "{{ ns }}" "{{ db_cluster }}")"
  kubectl exec -it --container database --namespace "{{ ns }}" "$primary" -- /bin/bash
