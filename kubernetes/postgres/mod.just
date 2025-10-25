set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

default_ns := 'database'
default_cluster := 'postgres'
default_cli_args := '--verbose --format=c --no-comments --clean --if-exists --no-owner --extension plpgsql'

[doc('Run pg_dump on the master instance of a CrunchyData Postgres cluster')]
crunchy-dump db_name ns='' db_cluster='' output_dir='.' cli_args='':
  ns_value="{{ default_ns }}"
  [[ -n "{{ ns }}" ]] && ns_value="{{ ns }}"
  cluster_value="{{ default_cluster }}"
  [[ -n "{{ db_cluster }}" ]] && cluster_value="{{ db_cluster }}"
  cli_flags="{{ default_cli_args }}"
  [[ -n "{{ cli_args }}" ]] && cli_flags="{{ cli_args }}"
  command -v kubectl >/dev/null || { echo 'kubectl is required' >&2; exit 1; }
  kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value >/dev/null
  primary=$(kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash -c "pg_dump --dbname {{ db_name }} ${cli_flags} --file /pgdata/{{ db_name }}.psql"
  kubectl cp --container database "$ns_value/$primary:/pgdata/{{ db_name }}.psql" "{{ output_dir }}/{{ db_name }}.psql"
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash -c 'rm -rf /pgdata/{{ db_name }}.psql'

[doc('Restore a pg_dump backup into a CrunchyData Postgres cluster')]
crunchy-restore db_name db_user file ns='' db_cluster='' cli_args='':
  if [[ ! -f "{{ file }}" ]]; then printf 'backup file not found: %s\n' "{{ file }}" >&2; exit 1; fi
  ns_value="{{ default_ns }}"
  [[ -n "{{ ns }}" ]] && ns_value="{{ ns }}"
  cluster_value="{{ default_cluster }}"
  [[ -n "{{ db_cluster }}" ]] && cluster_value="{{ db_cluster }}"
  kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value >/dev/null
  primary=$(kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value -o jsonpath='{.items[0].metadata.name}')
  restore_flags="{{ cli_args }}"
  if [[ -z "$restore_flags" ]]; then restore_flags=$(printf -- '--verbose --format=c --clean --if-exists --no-owner --role %s' "{{ db_user }}"); fi
  kubectl cp --container database "{{ file }}" "$ns_value/$primary:/pgdata/restore-{{ db_name }}.psql"
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash -c 'echo "ALTER DATABASE \"{{ db_name }}\" OWNER TO \"{{ db_user }}\";" | psql'
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash -c "pg_restore --dbname {{ db_name }} ${restore_flags} /pgdata/restore-{{ db_name }}.psql"
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash -c 'rm -rf /pgdata/restore-{{ db_name }}.psql'

[doc('Open a shell inside the CrunchyData master pod')]
crunchy-exec ns='' db_cluster='':
  ns_value="{{ default_ns }}"
  [[ -n "{{ ns }}" ]] && ns_value="{{ ns }}"
  cluster_value="{{ default_cluster }}"
  [[ -n "{{ db_cluster }}" ]] && cluster_value="{{ db_cluster }}"
  kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value >/dev/null
  primary=$(kubectl get pods -n "$ns_value" -l postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$cluster_value -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -it --container database --namespace "$ns_value" "$primary" -- /bin/bash
