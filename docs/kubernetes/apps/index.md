# Kubernetes Applications

Applications are grouped by domain under `kubernetes/apps/<domain>/`. Each stack is a `ks.yaml` plus an `app/` directory, registered in the domain `kustomization.yaml`.

## Active domains

- `selfhosted`: internal productivity and automation apps.
- `downloads`: media indexers, clients, and automation tools.
- `home-automation`: Home Assistant and speech/IoT services.
- `media`: media servers and supporting services.
- `observability`: metrics, logs, dashboards, exporters.
- `network`: gateway, DNS automation, and edge routing.
- `database`: Crunchy Postgres and EMQX (MQTT).
- `authentik`: identity and SSO.
- `actions-runner-system`: self-hosted GitHub Actions runners.
- `system`, `system-controllers`, `system-upgrade`: cluster utility controllers and tuppr upgrades.

Platform namespaces (`kube-system`, `flux-system`, `cert-manager`, `external-secrets`, `openebs`, `rook-ceph`) are covered in [Infrastructure](../infrastructure/index.md).

## Stack conventions

1. Prefer the bjw-s app-template chart unless there is a documented exception.
2. Keep Kustomization scope narrow to one stack.
3. Use `ExternalSecret` for credentials and token material.
4. Add required Cilium labels before creating custom network policies.
5. Add VolSync components for stateful workloads that need snapshots.

## New app rollout checklist

1. Create `kubernetes/apps/<domain>/<app>/`.
2. Add `ks.yaml` and `app/` manifests, then register `./<app>/ks.yaml` in the domain `kustomization.yaml`.
3. Wire any required shared components via `components:`.
4. Render with `just flux build-ks dir=<domain>/<app>`.
5. Merge and let Flux reconcile, or apply early with `just flux apply-ks dir=<domain>/<app>` (changes the live cluster).
6. Run `pre-commit run -a` before merge.

## Useful references

- `kubernetes/apps/selfhosted/n8n/` for app-template pattern.
- `kubernetes/apps/kube-system/cilium/netpols/` for clusterwide Cilium policies.
