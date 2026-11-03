<!-- Generated: 2026-11-03 | Files scanned: 95 (helmreleases, ocirepositories, workflows, tool config) | Token estimate: ~700 -->

# Dependencies

## Chart sources

- `HelmRepository bjw-s-labs` (`kubernetes/flux/repositories/helm/`): app-template for most apps.
- Per-stack `app/ocirepository.yaml` for upstream OCI charts, including:
  - `quay.io/cilium`, `quay.io/jetstack` (cert-manager), `ghcr.io/coredns`, `ghcr.io/controlplaneio-fluxcd` (flux-operator/instance)
  - `ghcr.io/prometheus-community` (kube-prometheus-stack, exporters), `ghcr.io/grafana`, `ghcr.io/victoriametrics`, `ghcr.io/fluent`
  - `ghcr.io/rook`, `docker.io/envoyproxy/gateway-helm`, `ghcr.io/external-secrets`, `ghcr.io/actions/actions-runner-controller-charts`
  - `ghcr.io/intel/helm-charts`, `ghcr.io/spegel-org`, `ghcr.io/stakater` (reloader), `ghcr.io/piraeusdatastore` (snapshot-controller)
  - `ghcr.io/home-operations/charts` (tuppr), `ghcr.io/bjw-s-labs/helm/multus`, `gsoci.azurecr.io/charts/giantswarm` (silence-operator)
  - `ghcr.io/home-operations/charts-mirror/external-dns` (still on the mirror)
- Bootstrap charts: `kubernetes/bootstrap/helmfile.d/{00-crds,01-apps}.yaml`.

## External services

| Service           | Used by                                    | Wiring                                        |
| ----------------- | ------------------------------------------ | --------------------------------------------- |
| 1Password Connect | all ExternalSecrets, Talos secrets (`op`)  | `external-secrets/onepassword-connect`        |
| Cloudflare        | public DNS, tunnel, ACME DNS-01            | externaldns-cloudflare, cloudflared, issuers  |
| OPNsense          | internal DNS                               | externaldns-internal webhook                  |
| Wasabi S3         | VolSync restic, pgBackRest                 | `components/volsync/wasabi`, PostgresCluster  |
| GitHub            | Flux source, Actions runners, Pages (docs) | FluxInstance, actions-runner-controller       |
| Authentik         | SSO for selected apps                      | `authentik/authentik`, `egress.home.arpa/sso` |
| External media VM | NFS media (Decypharr)                      | radarr, sonarr, jellyfin, plex                |
| Synology NAS      | NFS downloads/media (down)                 | downloads apps, jellyfin, plex                |

## Tooling

- `.mise.toml`: uv, gum, yamlfmt, stern, flux-local (pipx); exports `KUBECONFIG`, `TALOSCONFIG`, `MINIJINJA_CONFIG_FILE`, `JUST_UNSTABLE`.
- Also required: just, kubectl, flux, helm, helmfile, yq, jq, talosctl, topf, minijinja-cli, sops, age, op.
- Docs: MkDocs + mkdocs-terminal (`requirements.txt`, `mkdocs.yml`), published to `docs.d-o-c.cloud`.

## CI (.github/workflows)

| Workflow                 | Trigger                      | Purpose                           |
| ------------------------ | ---------------------------- | --------------------------------- |
| `flux-local.yaml`        | pull_request                 | render + diff Flux resources      |
| `lint.yaml`              | pull_request, dispatch       | pre-commit hooks                  |
| `codeql.yml`             | push, PR, schedule, dispatch | CodeQL analysis                   |
| `pre-pull-images.yaml`   | pull_request                 | pre-pull changed images on nodes  |
| `labeler.yaml`           | pull_request                 | path-based PR labels              |
| `schedule-renovate.yaml` | schedule, dispatch           | run Renovate                      |
| `deploy-mkdocs.yml`      | push, dispatch               | build/deploy docs to GitHub Pages |

## Renovate

`renovate.json5` + `.renovate/{allowedVersions,autoMerge,customManagers,grafanaDashboards,groups,versioning}.json5`; helper scripts in `scripts/renovate/`.
