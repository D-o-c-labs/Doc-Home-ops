# Doc Home Ops

Doc Home Ops is the GitOps source of truth for the `doc-home-ops` Talos/Kubernetes cluster running on a highly available control plane. The repository wires together Talos machine definitions, FluxCD, bjw-s app-template workloads, External Secrets, and Cilium network policies to manage a self-hosted homelab platform end to end.

The cluster structure, task automation, and general GitOps workflow are heavily inspired by bjw-s' [home-ops](https://github.com/bjw-s-labs/home-ops) repository.

## Highlights

- Talos-managed control plane with declarative machine configs and automated upgrades.
- FluxCD GitOps pipeline with per-domain Kustomizations and shared component overlays.
- Bordered blast radius via Cilium network policies and namespace-scoped Kustomizations.
- Secrets sourced from 1Password via External Secrets and encrypted with SOPS/age in Git.
- Taskfile-driven workflows for Talos lifecycle, Flux operations, VolSync snapshots, and housekeeping.
- GitHub Actions (lint, flux-local, CodeQL, renovate) to validate changes before they reach the cluster.

## Prerequisites

Install the required tooling before making changes:

- [`mise`](https://mise.jdx.dev) to sync tool versions defined in `.mise.toml` (installs `uv`, `flux-local`, and exports `KUBECONFIG`/`TALOSCONFIG`).
- [`task`](https://taskfile.dev) to execute the automation tasks in `Taskfile.yaml`.
- Kubernetes toolchain: `kubectl`, `flux`, `flux-local`, `helmfile`, `helm`, `yq`, `jq`, `stern`.
- Talos utilities: `talosctl`, `talhelper`, `minijinja-cli`.
- Secrets tooling: `sops`, `age`, and the 1Password CLI (`op`).

Run `mise install` followed by `task --list` to confirm everything is available.

## Repository Layout

| Path                     | Purpose                                                                                                                                                                                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubernetes/apps/`       | Application stacks grouped by domain (e.g. `media/`, `monitoring/`, `network/`). Each stack includes `ks.yaml`, `kustomization.yaml`, and an `app/` folder with manifests such as `helmrelease.yaml`, `externalsecret.yaml`, and network policy resources. |
| `kubernetes/components/` | Reusable Kustomize components (namespaces, Flux alerts, VolSync boilerplate). Referenced from app stacks via `components:` blocks.                                                                                                                         |
| `kubernetes/bootstrap/`  | Helmfile-driven cluster bootstrap (Cilium, CoreDNS, cert-manager, flux-operator) plus supporting templates and environment.                                                                                                                                |
| `kubernetes/flux/`       | Flux `GitRepository` and `Kustomization` definitions that reconcile the rest of the repository.                                                                                                                                                            |
| `kubernetes/talos/`      | Talos cluster configuration (`talconfig.yaml`), secrets wiring (`talhelper-secrets.env`), and generated machine configs in `clusterconfig/`.                                                                                                               |
| `.taskfiles/`            | Namespaced Taskfile extensions covering Flux, Kubernetes maintenance, Talos lifecycle, SOPS rotation, and VolSync operations.                                                                                                                              |
| `docs/`                  | Space for architecture notes and runbooks; expand as new components are added.                                                                                                                                                                             |
| `.github/workflows/`     | CI pipelines for linting, flux-local diff/test, CodeQL, image pre-pulls, Renovate scheduling, and label automation.                                                                                                                                        |

## GitOps Flow

1. **Talos** provisions the control plane using machine configs rendered from `talconfig.yaml` and 1Password secrets.
2. **Bootstrap** applies the Helmfile in `kubernetes/bootstrap/` to install foundational controllers (Cilium, CoreDNS, cert-manager, Flux Operator/Instance).
3. **Flux** reconciles `kubernetes/flux/cluster/cluster.yaml`, which in turn syncs all app stacks under `kubernetes/apps/` and supporting repositories.
4. **Applications** rely on the bjw-s app-template or upstream charts, with configuration and credentials pulled from External Secrets and VolSync for stateful data.
5. **Automation** via GitHub Actions and `task` commands keeps rendered manifests, secrets, and snapshots healthy.

## Talos Lifecycle

Manage Talos with the bundled tasks in `.taskfiles/talos/Taskfile.yaml`:

- Generate machine configs (requires 1Password session):

  ```bash
  task talos:generate-clusterconfig
  ```

- Apply configs cluster-wide or node-specific:

  ```bash
  task talos:apply-clusterconfig [DRY_RUN=true]
  task talos:apply-node NODE=zeus.piscio.net
  ```

- Upgrade Talos on a node:

  ```bash
  task talos:upgrade-node NODE=zeus.piscio.net
  ```

The helper environment file `kubernetes/talos/talhelper-secrets.env` maps Talos secrets to 1Password items so nothing sensitive lives in Git.

## Flux & Application Stacks

- Each domain under `kubernetes/apps/` owns its namespace `kustomization.yaml` and delegates workload specifics to nested `ks.yaml` entries.
- Workloads typically use the [`bjw-s/app-template`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common) via a `HelmRelease` in `app/helmrelease.yaml` plus overlays for PVCs, ConfigMaps, and network policies.
- Shared behavior (Flux alerting, VolSync replication, namespace creation) is composed with `components` references.
- External dependencies (databases, monitoring exporters, ingress gateways, etc.) live alongside application code so Flux can reconcile the full graph.
- Required Cilium network policies are included either as standalone manifests or via annotations, aligning with the cluster-wide policies in `kubernetes/apps/kube-system/cilium/netpols/`.

When introducing a new service:

1. Create a new directory under the appropriate domain with `kustomization.yaml`, `ks.yaml`, and an `app/` folder.
2. Start from an existing app-template example (e.g. `kubernetes/apps/selfhosted/n8n/app/helmrelease.yaml`).
3. Add `components` such as `../../../../components/namespace` or `../../../../components/volsync` as needed.
4. Provide secrets via an `externalsecret.yaml` referencing a 1Password item, and ensure SOPS encryption if storing credentials locally.
5. Add or reference the necessary Cilium network policies to constrain ingress/egress.
6. Run `task flux:build-ks DIR=<domain/...>` to validate before opening a PR.

## Secrets and Credentials

- SOPS rules in `.sops.yaml` enforce age encryption for any `*.sops.yaml` files, with keys shared between the repo owner and cluster automation user.
- `kubernetes/apps/*/externalsecret.yaml` bridge secrets from 1Password into Kubernetes. Use descriptive names and keep ExternalSecrets in place even when values are defined elsewhere.
- To rotate secrets, decrypt, edit, and re-encrypt the file:

  ```bash
  sops kubernetes/apps/<path>/externalsecret.sops.yaml
  ```

  or run the bulk helper:

  ```bash
  task sops:re-encrypt
  ```

- Talos bootstrap secrets come from 1Password via `op run` invocations in the Taskfiles.

## Operations & Maintenance

Key automation entry points:

- Flux render/apply/delete for a specific stack:

  ```bash
  task flux:build-ks DIR=selfhosted/n8n
  task flux:apply-ks DIR=selfhosted/n8n
  task flux:delete-ks DIR=selfhosted/n8n NAME=n8n
  ```

- Kubernetes cleanup and ExternalSecret maintenance:

  ```bash
  task k8s:cleanup-pods
  task k8s:sync-externalsecrets
  ```

- VolSync snapshot management:

  ```bash
  task volsync:snapshot APP=n8n NS=selfhosted
  task volsync:list APP=n8n NS=selfhosted
  task volsync:restore APP=n8n NS=selfhosted PREVIOUS=2024-01-01T00:00:00Z
  ```

- Bootstrap sequence for a new cluster:

  ```bash
  task k8s-bootstrap:talos
  task k8s-bootstrap:apps
  ```

## Automation & CI

- **Pre-commit** (`.pre-commit-config.yaml`) runs yamllint, prettier, whitespace checks, and secret scanners. Execute `pre-commit run -a` locally before opening a PR.
- **GitHub Actions**:
  - `flux-local.yaml` renders and diffs Flux resources for pull requests touching `kubernetes/**`.
  - `lint.yaml` runs pre-commit hooks in CI.
  - `codeql.yml` performs static analysis on the repository.
  - `pre-pull-images.yaml` primes frequently used container images.
  - `schedule-renovate.yaml` triggers Renovate to file dependency PRs.
- **Renovate** configuration in `renovate.json5` keeps Talos, Helm charts, and container images up to date using shared presets from bjw-s and repo-local rules.

## Conventions

- YAML uses two spaces, LF endings, lowercase-kebab-case resource names, and `app.kubernetes.io/*` labels wherever possible.
- Prefer bjw-s app-template charts unless there is a documented exception.
- Commit messages follow Conventional Commit syntax (`feat(selfhosted/n8n): ...`).
- Keep changes scoped to a single app or namespace per PR when possible, and include Flux build output in the description.
- Always apply or reference Cilium network policies for new services to ensure least-privilege traffic flows.

## Validation Checklist

Before merging changes:

1. `mise install` (only needed once per environment).
2. `pre-commit run -a` to satisfy formatting, linting, and secret policies.
3. `task flux:build-ks DIR=<path>` to render and validate the affected Kustomization(s).
4. (Optional) `task flux:apply-ks DIR=<path>` against a test cluster for a server-side dry run.
5. For Talos modifications, `task talos:generate-clusterconfig` followed by `task talos:apply-clusterconfig DRY_RUN=true`.
6. Capture any relevant Flux diff output or task logs in the PR description.

## Further Reading

- Extend documentation under `docs/` for runbooks, network maps, or architecture decisions.
- Review existing stacks (e.g. `kubernetes/apps/monitoring/`, `kubernetes/apps/network/`) for patterns to reuse.
- Consult the upstream projects referenced here:
  - [Talos Linux](https://www.talos.dev)
  - [FluxCD](https://fluxcd.io)
  - [bjw-s Helm Charts](https://github.com/bjw-s-labs/helm-charts)
  - [External Secrets Operator](https://external-secrets.io)
  - [Cilium](https://cilium.io)
