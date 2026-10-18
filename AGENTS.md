<!--
Canonical agent instructions for every coding agent (Codex, OpenCode, Claude Code).
CLAUDE.md imports this file. Keep it short: only facts an agent can't derive from the repo.
-->

# Doc-Home-ops

Flux GitOps repository for a Talos Kubernetes home cluster. Flux reconciles `kubernetes/flux/`, which points at the stacks under `kubernetes/apps/<namespace>/<app>/`.

## Commands

- `mise install` installs the toolchain and exports `KUBECONFIG`/`TALOSCONFIG`; run commands from the repo root.
- `just -l` lists recipes (modules: `flux`, `k8s`, `talos`, `sops`, `volsync`, `postgres`, `k8s-bootstrap`).
- `just flux build-ks dir=<namespace>/<app>` renders and validates one stack. Run it after every manifest change; it is the main check.
- `pre-commit run -a` runs yamllint, prettier, markdownlint and gitleaks. It must pass before committing.
- `just flux apply-ks dir=<namespace>/<app>` applies to the live cluster. Only run it when asked.

## Stacks

- Copy `kubernetes/apps/selfhosted/n8n/` as the reference layout: `ks.yaml` plus `app/` (`helmrelease.yaml`, `externalsecret.yaml`, `networkpolicy.yaml`, `kustomization.yaml`).
- Register a new `ks.yaml` in `kubernetes/apps/<namespace>/kustomization.yaml`.
- Use the bjw-s app-template chart for HelmReleases unless told otherwise.
- `ks.yaml` `postBuild.substitute` supplies `${APP}`, `${HOSTNAME}` and the VolSync variables; reuse `kubernetes/components/` (`volsync`, `namespace`, `flux/alerts`) instead of copying manifests.
- Expose apps with an app-template `route:` whose parentRef is `envoy-internal` (LAN only) or `envoy-external` (public, through cloudflared).
- Renovate owns image and chart version bumps; don't bump unrelated versions in a feature change.

## Secrets

- IMPORTANT: never commit plaintext secrets.
- App secrets come from 1Password via `ExternalSecret` using the `onepassword` ClusterSecretStore; Postgres credentials use `crunchy-pgo-secrets`.
- `*.sops.yaml` files are age-encrypted. Edit them with `sops` and rotate with `just sops re-encrypt`.

## Cilium network policy

Grant access by adding pod labels (app-template `controllers.<name>.pod.labels` or `defaultPodOptions.labels`) that match the clusterwide policies in `kubernetes/apps/kube-system/cilium/netpols/`. A pod with any `egress.home.arpa/*` label becomes egress default-deny, so it also needs `egress.home.arpa/kubedns` (the cluster-wide DNS default is not deployed yet).

| Label (`: allow`)                   | Allows                                                                                |
| ----------------------------------- | ------------------------------------------------------------------------------------- |
| `egress.home.arpa/kubedns`          | kube-dns (TCP/UDP 53)                                                                 |
| `egress.home.arpa/internet`         | public internet (non-RFC1918)                                                         |
| `egress.home.arpa/world`            | Cilium `world` entity                                                                 |
| `egress.home.arpa/lan`              | `192.168.32.0/24`, `192.168.3.0/24`, `192.168.4.0/24`, `192.168.40.0/24`              |
| `egress.home.arpa/domus-vlan`       | `192.168.40.0/24`                                                                     |
| `egress.home.arpa/synology`         | `piscionas.piscio.net`, `192.168.32.201/32`                                           |
| `egress.home.arpa/apiserver`        | kube-apiserver (6443)                                                                 |
| `egress.home.arpa/envoy-internal`   | Envoy internal gateway (80, 443, 10080, 10443)                                        |
| `egress.home.arpa/sso`              | Authentik and `auth.piscio.net`                                                       |
| `egress.home.arpa/postgres-cluster` | Crunchy Postgres/PgBouncer on 5432 (defined in `database/crunchy-postgres-operator/`) |
| `ingress.home.arpa/gateway-route`   | Envoy gateways in namespace `network`                                                 |
| `ingress.home.arpa/lan`             | the LAN CIDRs above                                                                   |
| `ingress.home.arpa/metrics`         | Prometheus in namespace `observability`                                               |
| `ingress.home.arpa/internet`        | public internet (non-RFC1918)                                                         |
| `ingress.home.arpa/world`           | Cilium `world` entity                                                                 |

Write an `app/networkpolicy.yaml` only when no label fits or tighter port/CIDR scope is needed. For cross-namespace traffic, update the policy on both sides.

## Live cluster

- Read-only inspection (`kubectl get/describe/logs`, `flux get`) is fine.
- Ask before anything that changes the cluster: `apply-ks`, deletes, reconcile/suspend/resume, scaling, and any Talos `apply-*`, `upgrade-*`, `reset-*` or `reboot-node` recipe.
- `just talos generate-clusterconfig` only regenerates machine configs locally (needs `talhelper` and `op`); it has no dry-run.

## Git

- Conventional Commits scoped by app or area: `fix(qbittorrent): ...`, `feat(n8n): ...`, `docs(cilium): ...`. `chore(container|helm|...)` scopes belong to Renovate.
- Keep each PR to one stack or domain. In the PR body, note any 1Password items or manual steps it needs.
