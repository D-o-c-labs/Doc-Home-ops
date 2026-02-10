# Doc Home Ops

Doc Home Ops is the GitOps source of truth for the `doc-home-ops` Talos/Kubernetes cluster running on a highly available control plane. The repository wires together Talos machine definitions, FluxCD, bjw-s app-template workloads, External Secrets, and Cilium network policies to manage a self-hosted homelab platform end to end.

The cluster structure, automation patterns, and general GitOps workflow are heavily inspired by bjw-s' [home-ops](https://github.com/bjw-s-labs/home-ops) repository.

## Highlights

- Talos-managed control plane with declarative machine configs and automated upgrades.
- FluxCD GitOps pipeline with per-domain Kustomizations and shared component overlays.
- Bordered blast radius via Cilium network policies and namespace-scoped Kustomizations.
- Secrets sourced from 1Password via External Secrets and encrypted with SOPS/age in Git.
- `just`-driven workflows for Talos lifecycle, Flux operations, VolSync snapshots, and housekeeping.
- GitHub Actions (lint, flux-local, CodeQL, renovate) to validate changes before they reach the cluster.

## Prerequisites

Install the required tooling before making changes:

- [`mise`](https://mise.jdx.dev) to sync tool versions defined in `.mise.toml` (installs `uv`, `flux-local`, and exports `KUBECONFIG`/`TALOSCONFIG`).
- [`just`](https://just.systems) to execute the automation recipes declared in `.justfile` and the `mod.just` modules.
- Kubernetes toolchain: `kubectl`, `flux`, `flux-local`, `helmfile`, `helm`, `yq`, `jq`, `stern`.
- Talos utilities: `talosctl`, `talhelper`, `minijinja-cli`.
- Secrets tooling: `sops`, `age`, and the 1Password CLI (`op`).

Run `mise install` followed by `just -l` to confirm everything is available.

## Repository Layout

| Path                     | Purpose                                                                                                                                                                                                                                                       |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubernetes/apps/`       | Application stacks grouped by domain (e.g. `media/`, `observability/`, `network/`). Each stack includes `ks.yaml`, `kustomization.yaml`, and an `app/` folder with manifests such as `helmrelease.yaml`, `externalsecret.yaml`, and network policy resources. |
| `kubernetes/components/` | Reusable Kustomize components (namespaces, Flux alerts, replacements transformers, VolSync boilerplate). Referenced from app stacks via `components:` blocks.                                                                                                 |
| `kubernetes/bootstrap/`  | Helmfile-driven cluster bootstrap (Cilium, CoreDNS, cert-manager, flux-operator) plus supporting templates and environment.                                                                                                                                   |
| `kubernetes/flux/`       | Flux `GitRepository` and `Kustomization` definitions that reconcile the rest of the repository.                                                                                                                                                               |
| `kubernetes/talos/`      | Talos cluster configuration (`talconfig.yaml`), secrets wiring (`talhelper-secrets.env`), and generated machine configs in `clusterconfig/`.                                                                                                                  |
| `kubernetes/*/mod.just`  | `just` automation modules for Flux stacks, Talos lifecycle, VolSync workflows, and supporting operations scoped to each domain.                                                                                                                               |
| `sops/mod.just`          | Repository-wide SOPS helpers (bulk re-encryption) exposed via `just`.                                                                                                                                                                                         |
| `docs/`                  | Space for architecture notes and runbooks; expand as new components are added.                                                                                                                                                                                |
| `.github/workflows/`     | CI pipelines for linting, flux-local diff/test, CodeQL, image pre-pulls, Renovate scheduling, and label automation.                                                                                                                                           |

## GitOps Flow

1. **Talos** provisions the control plane using machine configs rendered from `talconfig.yaml` and 1Password secrets.
2. **Bootstrap** applies the Helmfile in `kubernetes/bootstrap/` to install foundational controllers (Cilium, CoreDNS, cert-manager, Flux Operator/Instance).
3. **Flux** reconciles `kubernetes/flux/cluster/cluster.yaml`, which in turn syncs all app stacks under `kubernetes/apps/` and supporting repositories.
4. **Applications** rely on the bjw-s app-template or upstream charts, with configuration and credentials pulled from External Secrets and VolSync for stateful data.
5. **Automation** via GitHub Actions and `just` recipes keeps rendered manifests, secrets, and snapshots healthy.

## Talos Lifecycle

Manage Talos operations with the `just talos` module:

- Generate machine configs (requires an active 1Password session):

  ```bash
  just talos generate-clusterconfig
  ```

- Apply configs cluster-wide or node-specific (optionally dry-run or insecure for bring-up):

  ```bash
  just talos apply-clusterconfig dry_run=true
  just talos apply-node node=zeus.piscio.net
  ```

- Upgrade Talos on a node:

  ```bash
  just talos upgrade-node node=zeus.piscio.net
  ```

The helper environment file `kubernetes/talos/talhelper-secrets.env` maps Talos secrets to 1Password items so nothing sensitive lives in Git.

## Flux & Application Stacks

- Each domain under `kubernetes/apps/` owns its namespace `kustomization.yaml` and delegates workload specifics to nested `ks.yaml` entries.
- Domain-level Kustomizations include the shared `../../components/replacements/ks.yaml` transformer so Flux Kustomizations inherit the namespace automatically—avoid setting `metadata.namespace` or `spec.targetNamespace` directly in `ks.yaml`.
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
6. Run `just flux build-ks dir=<domain/...>` to validate before opening a PR.

## Secrets and Credentials

- SOPS rules in `.sops.yaml` enforce age encryption for any `*.sops.yaml` files, with keys shared between the repo owner and cluster automation user.
- `kubernetes/apps/*/externalsecret.yaml` bridge secrets from 1Password into Kubernetes. Use descriptive names and keep ExternalSecrets in place even when values are defined elsewhere.
- To rotate secrets, decrypt, edit, and re-encrypt the file:

  ```bash
  sops kubernetes/apps/<path>/externalsecret.sops.yaml
  ```

  or run the bulk helper:

  ```bash
  just sops re-encrypt
  ```

- Talos bootstrap secrets come from 1Password via `op run` inside the `just talos generate-clusterconfig` recipe.

## Operations & Maintenance

Key automation entry points:

- Flux render/apply/delete for a specific stack:

  ```bash
  just flux build-ks dir=selfhosted/n8n
  just flux apply-ks dir=selfhosted/n8n
  just flux delete-ks dir=selfhosted/n8n name=n8n
  ```

- Kubernetes cleanup and ExternalSecret maintenance:

  ```bash
  just k8s cleanup-pods
  just k8s sync-externalsecrets
  ```

- VolSync snapshot management:

  ```bash
  just volsync snapshot app=n8n ns=selfhosted
  just volsync list app=n8n ns=selfhosted
  just volsync restore app=n8n ns=selfhosted previous=2024-01-01T00:00:00Z
  ```

- Bootstrap sequence for a new cluster:

  ```bash
  just k8s-bootstrap talos
  just k8s-bootstrap apps
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
3. `just flux build-ks dir=<path>` to render and validate the affected Kustomization(s).
4. (Optional) `just flux apply-ks dir=<path>` against a test cluster for a server-side dry run.
5. For Talos modifications, `just talos generate-clusterconfig` followed by `just talos apply-clusterconfig dry_run=true`.
6. Capture any relevant Flux diff output or `just` logs in the PR description.

## Further Reading

- Extend documentation under `docs/` for runbooks, network maps, or architecture decisions.
- Review existing stacks (e.g. `kubernetes/apps/observability/`, `kubernetes/apps/network/`) for patterns to reuse.
- Review `docs/kubernetes/observability.md` for log and metrics stack details and runbooks.
- Consult the upstream projects referenced here:
  - [Talos Linux](https://www.talos.dev)
  - [FluxCD](https://fluxcd.io)
  - [bjw-s Helm Charts](https://github.com/bjw-s-labs/helm-charts)
  - [External Secrets Operator](https://external-secrets.io)
  - [Cilium](https://cilium.io)

## Just Automation Reference

Each `just` module exposes reusable workflows. The examples below assume you are at the repository root with `mise`-provisioned tooling on your `PATH`.

### Flux (`just flux ...`)

- `build-ks`: Render a stack for inspection before committing (`just flux build-ks dir=selfhosted/n8n`).
- `apply-ks`: Apply a stack to the cluster using server-side apply (`just flux apply-ks dir=selfhosted/n8n`).
- `delete-ks`: Remove a stack by piping the rendered manifest to `kubectl delete` (`just flux delete-ks dir=selfhosted/n8n name=n8n`).
- `suspend-ks-all`: Pause reconciliation across namespaces (e.g. `just flux suspend-ks-all`).
- `resume-ks-all`: Resume reconciliation across namespaces (e.g. `just flux resume-ks-all`).

### Kubernetes (`just k8s ...`)

- Use the `sync-*` helpers when you only need Flux to retry reconciliation with the currently fetched revision. Reach for the `reconcile-*` helpers when you want Flux to fetch sources with `--with-source`, rebuild manifests, and apply immediately.

- `browse-pvc`: Mount a PVC into an ephemeral Alpine shell (`just k8s browse-pvc namespace=media claim=tdarr-config`).
- `node-shell`: Spawn a debug pod on a node (`just k8s node-shell node=k8s-master-01`).
- `cleanup-pods`: Remove pods stuck in Failed/Pending/Succeeded phases (`just k8s cleanup-pods`).
- `sync-externalsecrets`: Force-refresh every ExternalSecret (`just k8s sync-externalsecrets`).
- `sync-all-hr`: Trigger HelmRelease reconciles across the cluster using the existing revision cached by Flux (`just k8s sync-all-hr`).
- `sync-all-ks`: Trigger Flux Kustomization reconciles across the cluster using the existing revision cached by Flux (`just k8s sync-all-ks`).
- `reconcile-hr`: Force a HelmRelease to pull its source, re-render the chart, and apply immediately (`just k8s reconcile-hr namespace=media name=unpackerr`).
- `reconcile-ks`: Force a Flux Kustomization to pull its source, rebuild manifests, and apply immediately (`just k8s reconcile-ks namespace=selfhosted name=n8n`).
- `reconcile-all-hr`: Loop every HelmRelease and perform a full `flux reconcile --with-source` refresh (`just k8s reconcile-all-hr`).
- `reconcile-all-ks`: Loop every Flux Kustomization and perform a full `flux reconcile --with-source` refresh (`just k8s reconcile-all-ks`).
- `snapshot`: Fan out VolSync snapshots for every replication source (`just k8s snapshot`).

### VolSync (`just volsync ...`)

- `list`: Launch a throw-away job to list snapshots for an app (`just volsync list app=n8n ns=selfhosted`).
- `snapshot`: Patch a replication source to take a snapshot, optionally waiting for completion (`just volsync snapshot app=n8n ns=selfhosted wait=true`).
- `snapshot-all`: Trigger non-blocking snapshots for every replication source (`just volsync snapshot-all`).
- `restore`: Perform a manual restore workflow and resync the associated workloads (`just volsync restore app=n8n ns=selfhosted previous=2024-01-01T00:00:00Z`).
- `unlock`: Clear restic locks after interrupted jobs (`just volsync unlock`).

### Talos (`just talos ...`)

- `generate-clusterconfig`: Render Talos machineconfigs via talhelper with 1Password secrets injected (`just talos generate-clusterconfig`).
- `apply-clusterconfig`: Apply generated machineconfigs with optional dry-run/insecure flags (`just talos apply-clusterconfig mode=auto dry_run=true`).
- `apply-node`: Patch a single node using the templated config (`just talos apply-node node=zeus.piscio.net -- --dry-run`).
- `apply-cluster`: Re-render configs on the fly and push to every node (`just talos apply-cluster`).
- `upgrade-node`: Perform an in-place Talos upgrade (`just talos upgrade-node node=zeus.piscio.net`).
- `upgrade-k8s`: Upgrade the control plane Kubernetes version (`just talos upgrade-k8s version=1.30.2`).
- `render-config`: Output the merged Talos config for a node (`just talos render-config node=zeus.piscio.net > /tmp/zeus.yaml`).

### Bootstrap (`just k8s-bootstrap ...`)

- `talos`: Apply bootstrap namespaces, CRDs, and Helm releases after machines are reachable (`just k8s-bootstrap talos`).
- `apps`: Apply the app bootstrap helmfile once the cluster is ready (`just k8s-bootstrap apps`).

### SOPS (`just sops ...`)

- `re-encrypt`: Decrypt and re-encrypt every `*.sops.yaml` in place (`just sops re-encrypt`).

### Crunchy Postgres (`just postgres ...`)

- `crunchy-dump`: Run `pg_dump` on the primary and copy it locally (`just postgres crunchy-dump db_name=immich ns=media`).
- `crunchy-restore`: Upload and restore a backup into the primary pod (`just postgres crunchy-restore db_name=immich db_user=immich file=backups/immich.psql`).
- `crunchy-exec`: Open an interactive shell in the Crunchy primary (`just postgres crunchy-exec ns=media`).
