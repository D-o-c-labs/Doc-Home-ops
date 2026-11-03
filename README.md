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
- Talos utilities: `talosctl`, [`topf`](https://postfinance.github.io/topf/), `minijinja-cli`.
- Secrets tooling: `sops`, `age`, and the 1Password CLI (`op`).

Run `mise install` followed by `just -l` to confirm everything is available.

## Repository Layout

| Path                     | Purpose                                                                                                                                                                                                                                                                                |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubernetes/apps/`       | Application stacks grouped by domain (e.g. `media/`, `observability/`, `network/`). Each stack has a `ks.yaml` and an `app/` folder (`helmrelease.yaml`, `externalsecret.yaml`, `networkpolicy.yaml`, `kustomization.yaml`); the domain `kustomization.yaml` registers each `ks.yaml`. |
| `kubernetes/components/` | Reusable Kustomize components (namespaces, Flux alerts, replacements transformers, VolSync boilerplate). Referenced from app stacks via `components:` blocks.                                                                                                                          |
| `kubernetes/bootstrap/`  | Helmfile-driven cluster bootstrap (Cilium, CoreDNS, cert-manager, flux-operator) plus supporting templates and environment.                                                                                                                                                            |
| `kubernetes/flux/`       | Flux `GitRepository` and `Kustomization` definitions that reconcile the rest of the repository.                                                                                                                                                                                        |
| `kubernetes/talos/`      | Talos cluster configuration for topf: nodes in `topf.yaml`, config patches in `all/` and `control-plane/`, and the 1Password secrets provider (`secrets.sh`).                                                                                                                          |
| `kubernetes/*/mod.just`  | `just` automation modules for Flux stacks, Talos lifecycle, VolSync workflows, and supporting operations scoped to each domain.                                                                                                                                                        |
| `sops/mod.just`          | Repository-wide SOPS helpers (bulk re-encryption) exposed via `just`.                                                                                                                                                                                                                  |
| `docs/`                  | MkDocs wiki published to `docs.d-o-c.cloud` (Talos, Kubernetes, runbooks, troubleshooting). `docs/CODEMAPS/` holds token-lean architecture maps that are excluded from the site.                                                                                                       |
| `.github/workflows/`     | CI pipelines for linting, flux-local diff/test, CodeQL, image pre-pulls, Renovate scheduling, label automation, and the docs site deploy.                                                                                                                                              |

## GitOps Flow

1. **Talos** provisions the control plane with machine configs that topf builds from `topf.yaml`, the patches and 1Password secrets.
2. **Bootstrap** applies the Helmfile in `kubernetes/bootstrap/` to install foundational controllers (Cilium, CoreDNS, cert-manager, Flux Operator/Instance).
3. **Flux** reconciles `kubernetes/flux/cluster/cluster.yaml`, which in turn syncs all app stacks under `kubernetes/apps/` and supporting repositories.
4. **Applications** rely on the bjw-s app-template or upstream charts, with configuration and credentials pulled from External Secrets and VolSync for stateful data.
5. **Automation** via GitHub Actions and `just` recipes keeps rendered manifests, secrets, and snapshots healthy.

## Talos Lifecycle

Manage Talos operations with the `just talos` module:

- Show what would change on the running nodes (requires 1Password access):

  ```bash
  just talos diff
  ```

- Apply cluster-wide or to one node; topf shows the diff and asks before applying:

  ```bash
  just talos apply
  just talos apply-node zeus
  ```

- Upgrade Talos on a node by hand (tuppr normally drives upgrades):

  ```bash
  just talos upgrade-node zeus
  ```

`kubernetes/talos/secrets.env` maps the Talos secrets to 1Password items; `secrets.sh` renders the bundle on demand for topf, so nothing sensitive lives in Git or on disk.

## Flux & Application Stacks

- Each domain under `kubernetes/apps/` owns its namespace `kustomization.yaml` and delegates workload specifics to nested `ks.yaml` entries.
- Domain-level Kustomizations include the shared `../../components/replacements/ks.yaml` transformer so Flux Kustomizations inherit the namespace automatically—avoid setting `metadata.namespace` or `spec.targetNamespace` directly in `ks.yaml`.
- Workloads typically use the [`bjw-s/app-template`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common) via a `HelmRelease` in `app/helmrelease.yaml` plus overlays for PVCs, ConfigMaps, and network policies.
- Shared behavior (Flux alerting, VolSync replication, namespace creation) is composed with `components` references.
- External dependencies (databases, monitoring exporters, ingress gateways, etc.) live alongside application code so Flux can reconcile the full graph.
- Required Cilium network policies are included either as standalone manifests or via `*.home.arpa/*` pod labels, aligning with the cluster-wide policies in `kubernetes/apps/kube-system/cilium/netpols/`.

When introducing a new service:

1. Create a new directory under the appropriate domain with a `ks.yaml` and an `app/` folder, copying `kubernetes/apps/selfhosted/n8n/` as the reference layout.
2. Register the new `ks.yaml` in the domain `kubernetes/apps/<domain>/kustomization.yaml`.
3. Add `components` such as `../../../../components/volsync` in `ks.yaml` as needed (the domain kustomization already adds `namespace` and `flux/alerts`).
4. Provide secrets via an `externalsecret.yaml` referencing a 1Password item (Postgres credentials come from the `crunchy-pgo-secrets` store).
5. Add the `*.home.arpa/*` pod labels for Cilium access, or an `app/networkpolicy.yaml` when no label fits.
6. Run `just flux build-ks dir=<domain>/<app>` to validate before opening a PR.

## Secrets and Credentials

- SOPS rules in `.sops.yaml` enforce age encryption for any `*.sops.yaml` files, with keys shared between the repo owner and cluster automation user.
- `kubernetes/apps/<domain>/<app>/app/externalsecret.yaml` bridge secrets from 1Password into Kubernetes through the `onepassword` ClusterSecretStore. Use descriptive names and keep ExternalSecrets in place even when values are defined elsewhere.
- The only SOPS file today is the Flux decryption key (`kubernetes/components/flux/sops/secret.sops.yaml`). To edit a SOPS file in place:

  ```bash
  sops kubernetes/components/flux/sops/secret.sops.yaml
  ```

  or run the bulk helper:

  ```bash
  just sops re-encrypt
  ```

- Talos secrets come from 1Password via `op run` in `kubernetes/talos/secrets.sh`, which topf calls as its secrets provider.

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
  just k8s sync-all-es
  ```

- VolSync snapshot management (arguments are positional: `app`, then `ns`; `previous` is the number of snapshots to skip, `0` = latest):

  ```bash
  just volsync snapshot n8n selfhosted
  just volsync list n8n selfhosted
  just volsync restore n8n 0 selfhosted
  ```

- Bootstrap a new cluster (runs `talos`, `kubernetes`, `kubeconfig`, `wait`, `namespaces`, `resources`, `crds`, `apps` in order; each step is also its own recipe):

  ```bash
  just k8s-bootstrap
  ```

## Automation & CI

- **Pre-commit** (`.pre-commit-config.yaml`) runs yamllint, prettier, whitespace checks, and secret scanners. Execute `pre-commit run -a` locally before opening a PR.
- **GitHub Actions**:
  - `flux-local.yaml` renders and diffs Flux resources for pull requests touching `kubernetes/**`.
  - `lint.yaml` runs pre-commit hooks in CI.
  - `codeql.yml` performs static analysis on the repository.
  - `pre-pull-images.yaml` primes frequently used container images.
  - `schedule-renovate.yaml` triggers Renovate to file dependency PRs.
  - `labeler.yaml` labels pull requests by path.
  - `deploy-mkdocs.yml` builds the MkDocs site and publishes it to GitHub Pages.
- **Renovate** configuration in `renovate.json5` keeps Talos, Helm charts, and container images up to date using shared presets from bjw-s and repo-local rules.

## Conventions

- YAML uses two spaces, LF endings, lowercase-kebab-case resource names, and `app.kubernetes.io/*` labels wherever possible.
- Prefer bjw-s app-template charts unless there is a documented exception.
- Commit messages follow Conventional Commit syntax scoped by app or area (`feat(n8n): ...`, `docs(cilium): ...`); `chore(container|helm|...)` scopes belong to Renovate.
- Keep changes scoped to a single app or namespace per PR when possible, and note any 1Password items or manual steps in the description.
- Always apply or reference Cilium network policies for new services to ensure least-privilege traffic flows.

## Validation Checklist

Before merging changes:

1. `mise install` (only needed once per environment).
2. `pre-commit run -a` to satisfy formatting, linting, and secret policies.
3. `just flux build-ks dir=<domain>/<app>` to render and validate the affected Kustomization(s).
4. (Optional) `just flux apply-ks dir=<domain>/<app>` applies to the live cluster ahead of Flux; use it only when you mean to deploy outside the PR flow.
5. For Talos modifications, `just talos diff` to review the change against the running nodes.
6. Capture any relevant Flux diff output or `just` logs in the PR description.

## Further Reading

- Extend documentation under `docs/` for runbooks, network maps, or architecture decisions.
- Review existing stacks (e.g. `kubernetes/apps/observability/`, `kubernetes/apps/network/`) for patterns to reuse.
- `docs/CODEMAPS/` maps the architecture, stacks and `dependsOn` graph, network paths, storage and external dependencies.
- Consult the upstream projects referenced here:
  - [Talos Linux](https://www.talos.dev)
  - [FluxCD](https://fluxcd.io)
  - [bjw-s Helm Charts](https://github.com/bjw-s-labs/helm-charts)
  - [External Secrets Operator](https://external-secrets.io)
  - [Cilium](https://cilium.io)

## Just Automation Reference

Recipe arguments are positional: `just k8s reconcile-ks selfhosted n8n`, not `ns=selfhosted name=n8n`. Only the `flux` module strips a `dir=`/`name=` prefix, so `just flux build-ks dir=selfhosted/n8n` also works. Run `just -l <module>` for the live list.

Use the `sync-*` helpers when Flux only needs to retry with the revision it already fetched; use `reconcile-*` to fetch sources (`--with-source`), rebuild and apply immediately.

<!-- AUTO-GENERATED: just --dump --dump-format json -->

### `just flux`

| Recipe           | Arguments                                | Description                                                               |
| ---------------- | ---------------------------------------- | ------------------------------------------------------------------------- |
| `apply-ks`       | `dir ns_flag="--all-namespaces" name=""` | Render and apply a Flux Kustomization stack                               |
| `build-ks`       | `dir ns_flag="--all-namespaces" name=""` | Render a Flux Kustomization stack to stdout                               |
| `delete-ks`      | `dir ns_flag="--all-namespaces" name=""` | Render and delete a Flux Kustomization stack                              |
| `resume-ks-all`  | `namespaces=""`                          | Resume all Flux Kustomizations, optionally scoped to specific namespaces  |
| `suspend-ks-all` | `namespaces=""`                          | Suspend all Flux Kustomizations, optionally scoped to specific namespaces |

### `just k8s`

| Recipe             | Arguments         | Description                                                                       |
| ------------------ | ----------------- | --------------------------------------------------------------------------------- |
| `apply-ks`         | `ns ks`           | Apply local Flux Kustomization                                                    |
| `browse-pvc`       | `namespace claim` | Browse a PVC                                                                      |
| `cleanup-pods`     | -                 | Clean up pods stuck in Failed, Pending, or Succeeded states (alias: `prune-pods`) |
| `delete-ks`        | `ns ks`           | Delete local Flux Kustomization                                                   |
| `node-shell`       | `node`            | Open a shell on a node                                                            |
| `reconcile-all-hr` | -                 | Reconcile all Flux HelmReleases                                                   |
| `reconcile-all-ks` | -                 | Reconcile all Flux Kustomizations                                                 |
| `reconcile-hr`     | `ns name`         | Reconcile Flux HelmRelease                                                        |
| `reconcile-ks`     | `ns name`         | Reconcile Flux Kustomization                                                      |
| `snapshot`         | -                 | Snapshot all VolSync replication sources                                          |
| `sync-all-es`      | -                 | Sync all ExternalSecrets (alias: `sync-externalsecrets`)                          |
| `sync-all-hr`      | -                 | Sync all Flux HelmReleases                                                        |
| `sync-all-ks`      | -                 | Sync all Flux Kustomizations                                                      |
| `sync-es`          | `ns name`         | Sync single ExternalSecret                                                        |
| `sync-hr`          | `ns name`         | Sync single Flux HelmRelease                                                      |
| `sync-ks`          | `ns name`         | Sync single Flux Kustomizations                                                   |

### `just k8s-bootstrap`

| Recipe       | Arguments     | Description                    |
| ------------ | ------------- | ------------------------------ |
| `apps`       | -             | Apply Helmfile Apps            |
| `crds`       | -             | Apply Helmfile CRDs            |
| `kubeconfig` | `lb="cilium"` | Fetch kubeconfig               |
| `kubernetes` | -             | Install Kubernetes             |
| `namespaces` | -             | Apply Kubernetes namespaces    |
| `resources`  | -             | Apply Kubernetes resources     |
| `talos`      | -             | Install Talos                  |
| `wait`       | -             | Wait for nodes to be not-ready |

### `just postgres`

| Recipe            | Arguments                                                                                   | Description                                                          |
| ----------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `crunchy-dump`    | `db_name output_dir="." ns=default_ns db_cluster=default_cluster cli_args=default_cli_args` | Run pg_dump on the master instance of a CrunchyData Postgres cluster |
| `crunchy-exec`    | `ns=default_ns db_cluster=default_cluster`                                                  | Open a shell inside the CrunchyData master pod                       |
| `crunchy-restore` | `db_name db_user file ns=default_ns db_cluster=default_cluster cli_args=""`                 | Restore a pg_dump backup into a CrunchyData Postgres cluster         |
| `pgadmin`         | `local_port=pgadmin_port ns=default_ns timeout="5m"`                                        | Run an on-demand local PGAdmin session and scale it down on exit     |
| `pgadmin-down`    | `ns=default_ns timeout="5m"`                                                                | Scale PGAdmin down and wait for its pod to terminate                 |
| `pgadmin-up`      | `ns=default_ns timeout="5m"`                                                                | Scale PGAdmin up and wait until it is ready                          |

### `just sops`

| Recipe       | Arguments | Description                                               |
| ------------ | --------- | --------------------------------------------------------- |
| `re-encrypt` | -         | Decrypt and re-encrypt every SOPS managed secret in-place |

### `just talos`

| Recipe           | Arguments            | Description                                                                                         |
| ---------------- | -------------------- | --------------------------------------------------------------------------------------------------- |
| `apply`          | `mode="auto"`        | Apply the Talos config to every node, one at a time (shows a diff and asks first)                   |
| `apply-node`     | `node mode="auto"`   | Apply the Talos config to one node, e.g. `just talos apply-node zeus` (shows a diff and asks first) |
| `defrag-etcd`    | `*nodes`             | Defragment etcd members sequentially with the current leader last                                   |
| `diff`           | -                    | Show the pending config changes against the running nodes without applying them                     |
| `download-image` | `version schematic`  | Download Talos machine image                                                                        |
| `gen-kubeconfig` | -                    | Generate kubeconfig for Talos cluster                                                               |
| `nodes`          | -                    | List the nodes with their Talos version, schematic and stage                                        |
| `reboot-node`    | `node`               | Reboot a node                                                                                       |
| `render`         | -                    | Render the machine configs to kubernetes/talos/rendered (plaintext secrets, delete after use)       |
| `reset-cluster`  | `mode="reboot"`      | Reset all nodes in the cluster                                                                      |
| `reset-node`     | `node mode="reboot"` | Reset a node                                                                                        |
| `schematic-ids`  | -                    | Print the schematic ID of each node from schematic.yaml                                             |
| `talosconfig`    | -                    | Generate kubernetes/talos/talosconfig from the secrets bundle                                       |
| `upgrade-k8s`    | `version`            | Upgrade Kubernetes version on the cluster                                                           |
| `upgrade-node`   | `node`               | Upgrade Talos on one node, e.g. `just talos upgrade-node zeus`                                      |

### `just volsync`

| Recipe         | Arguments                      | Description                                                     |
| -------------- | ------------------------------ | --------------------------------------------------------------- |
| `list`         | `app ns="default"`             | List VolSync snapshots for an application                       |
| `restore`      | `app previous ns="default"`    | Restore a VolSync snapshot for an application                   |
| `snapshot`     | `app ns="default" wait="true"` | Trigger a VolSync snapshot for an application                   |
| `snapshot-all` | -                              | Trigger VolSync snapshots for every application without waiting |
| `unlock`       | -                              | Unlock all VolSync replication sources across the cluster       |

<!-- /AUTO-GENERATED -->
