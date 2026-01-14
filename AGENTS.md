# Repository Guidelines

## Project Structure & Module Organization

- `kubernetes/apps/<domain>/<app>/` houses Flux-ready app stacks; each stack keeps `ks.yaml`, `kustomization.yaml`, and an `app/` folder for HelmRelease, ExternalSecret, and NetPol manifests.
- `kubernetes/components/` provides reusable overlays (namespaces, VolSync, alerts) that app stacks import via `components:`.
- `kubernetes/bootstrap/` contains the Helmfile bootstrap for core controllers, while `kubernetes/flux/` defines GitRepositories and Kustomizations that reconcile the cluster.
- `.justfile` and the `mod.just` modules under `kubernetes/**` and `sops/` expose automation recipes; `docs/` stores architecture notes and runbooks.

## Build, Test, and Development Commands

- `mise install` syncs tool versions defined in `.mise.toml` and exports `KUBECONFIG`/`TALOSCONFIG`.
- `just -l` lists available recipes grouped by module.
- `just flux build-ks dir=<domain>/<app>` renders and validates a Flux Kustomization before committing.
- `just flux apply-ks dir=<domain>/<app>` applies a single stack after review; pair with `just flux delete-ks dir=<domain>/<app> name=<ks>` for teardown.
- `pre-commit run -a` mirrors CI linting (yamllint, prettier, secrets scan) and should pass before every PR.

## Coding Style & Naming Conventions

- YAML uses two-space indentation, lowercase-kebab-case resource names, and consistent `app.kubernetes.io/*` labels.
- Keep Flux Kustomization scopes narrow; favor bjw-s app-template HelmReleases unless the README documents an exception.
- Secrets files ending in `.sops.yaml` must remain encrypted with age; never commit decrypted material.

## Testing Guidelines

- Prefer local diffs via `just flux build-ks` and `flux-local diff` (invoked by CI) to confirm reconciles are clean.
- For Talos lifecycle changes, run `just talos generate-clusterconfig` in dry-run mode before applying.
- Include resulting YAML or command output snippets in the PR description when touching critical paths.

## Commit & Pull Request Guidelines

- Follow Conventional Commits (`feat(<domain/app>): ...`); scope paths (`kubernetes/apps/...`) keep history searchable.
- Each PR should isolate a domain or service, include Flux build output, link relevant issues, and note required secrets or follow-up steps.
- Request reviewers familiar with the touched stack and ensure CI (lint, flux-local, CodeQL) is green prior to merge.

## Service Deployment Guidelines

- **Helm Chart**: Default to the [bjw-s app-template chart](https://github.com/bjw-s-labs/helm-charts/tree/main) unless explicity requested.
- **Structure**: Mirror the layout used in `kubernetes/apps/downloads`, `.../home-automation`, `.../media`, and `.../selfhosted`; include `ks.yaml`, `kustomization.yaml`, and an `app/` directory for HelmRelease, ExternalSecret, and policy manifests.
- **Network Security**: Start with shared policies under `kubernetes/apps/kube-system/cilium/netpols/`, then add service-specific rules and pod annotations to keep ingress/egress minimal. Ensure not to duplicate the policies (e.g. `ingress.home.arpa/gateway-route: allow` annotation has to be used to allow traffic from envoy gateway. It is useless to replicate this in a dedicated `networkpolicy.yaml` file)
- **Inter-service Communication**: Update network rules for every participant when enabling cross-namespace traffic; document the rationale in the PR.
- **Documentation**: Use the `context7` documentation tool to confirm controller behavior or chart values before diverging from established patterns.

## Security & Configuration Tips

- Use `just sops re-encrypt` to rotate secrets safely, and reference 1Password items via ExternalSecret manifests.
- After applying changes, verify Cilium cluster policies and Talos configs still enforce the intended least-privilege posture.
