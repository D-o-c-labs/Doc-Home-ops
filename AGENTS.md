# Repository Guidelines

## Project Structure & Module Organization

- `kubernetes/apps/<domain>/<app>/` houses Flux-ready app stacks (for example `kubernetes/apps/selfhosted/n8n/`); each stack keeps `ks.yaml`, `kustomization.yaml`, and an `app/` folder for HelmRelease, ExternalSecret, and NetworkPolicy manifests.
- `kubernetes/components/` provides reusable overlays (namespaces, VolSync, alerts) that app stacks import via `components:`.
- `kubernetes/bootstrap/` contains the Helmfile bootstrap for core controllers, while `kubernetes/flux/` defines GitRepositories and Kustomizations that reconcile the cluster.
- `.justfile` and the `mod.just` modules under `kubernetes/**` and `sops/` expose automation recipes; `docs/` stores architecture notes and runbooks.

## Quick Workflow (New or Updated Stack)

- Add or update the stack in `kubernetes/apps/<domain>/<app>/` with `ks.yaml`, `kustomization.yaml`, and `app/` manifests.
- Prefer the bjw-s app-template HelmRelease unless the README documents an exception.
- Apply required Cilium access by setting the matching pod label (see Cilium section) before writing a custom `app/networkpolicy.yaml`.
- Render locally with `just flux build-ks dir=<domain>/<app>` and review the output.
- Apply with `just flux apply-ks dir=<domain>/<app>` and run `pre-commit run -a` before pushing.

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

- **Helm Chart**: Default to the [bjw-s app-template chart](https://github.com/bjw-s-labs/helm-charts/tree/main) unless explicitly requested.
- **Structure**: Mirror the layout used in `kubernetes/apps/downloads`, `.../home-automation`, `.../media`, and `.../selfhosted`; include `ks.yaml`, `kustomization.yaml`, and an `app/` directory for HelmRelease, ExternalSecret, and policy manifests.
- **Network Security**: Start with shared policies under `kubernetes/apps/kube-system/cilium/netpols/` and apply the matching pod labels. Only add a service-specific `app/networkpolicy.yaml` if no existing clusterwide rule fits.
- **Inter-service Communication**: Update network rules for every participant when enabling cross-namespace traffic; document the rationale in the PR.
- **Documentation**: Use the Context7 MCP server to confirm controller behavior or chart values before diverging from established patterns.

## Cilium Network Policy Guidance

- Use existing CiliumClusterwideNetworkPolicy rules first by applying the matching pod label (`egress.home.arpa/*` or `ingress.home.arpa/*`). Most charts expose this as `podLabels`; if not, patch labels in via Kustomize.
- Define a custom `app/networkpolicy.yaml` only when no clusterwide rule fits or you need tighter port/CIDR restrictions; document the rationale in the PR.
- When enabling cross-namespace traffic, update both sides of the policy and note the intent in the PR.

### Clusterwide Cilium Rules (Label -> Intent)

- `egress.home.arpa/apiserver: allow` -> egress to kube-apiserver (entity + host:6443).
- `egress.home.arpa/kubedns: allow` -> DNS to kube-dns (TCP/UDP 53).
- `egress.home.arpa/internet: allow` -> egress to public internet (non-RFC1918).
- `egress.home.arpa/world: allow` -> egress to `world` entity.
- `egress.home.arpa/lan: allow` -> egress to LAN CIDRs `192.168.32.0/24`, `192.168.3.0/24`, `192.168.4.0/24`, `192.168.40.0/24`.
- `egress.home.arpa/domus-vlan: allow` -> egress to `192.168.40.0/24`.
- `egress.home.arpa/synology: allow` -> egress to `piscionas.piscio.net` and `192.168.32.201/32`.
- `egress.home.arpa/envoy-internal: allow` -> egress to Envoy internal gateway ports `80`, `443`, `10080`, `10443`.
- `egress.home.arpa/sso: allow` -> egress to Authentik + `auth.piscio.net` (via Envoy).
- `ingress.home.arpa/gateway-route: allow` -> ingress from Envoy gateway (namespace `network`).
- `ingress.home.arpa/lan: allow` -> ingress from LAN CIDRs `192.168.32.0/24`, `192.168.3.0/24`, `192.168.4.0/24`, `192.168.40.0/24`.
- `ingress.home.arpa/metrics: allow` -> ingress from Prometheus in namespace `observability`.

## Security & Configuration Tips

- Use `just sops re-encrypt` to rotate secrets safely, and reference 1Password items via ExternalSecret manifests.
- After applying changes, verify Cilium cluster policies and Talos configs still enforce the intended least-privilege posture.
