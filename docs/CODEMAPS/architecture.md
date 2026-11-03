<!-- Generated: 2026-11-03 | Files scanned: 543 | Token estimate: ~750 -->

# Architecture

Flux GitOps monorepo for one Talos cluster (`doc-home-ops`). No application code: everything is Kubernetes manifests, Talos patches and `just` recipes.

## Layers

```text
zeus, ares, athena (all control-plane, schedulable)
  └─ Talos v1.14.4 (kubernetes/talos, built by topf)  ─ k8s v1.36.2
      └─ bootstrap helmfile (kubernetes/bootstrap): cilium → coredns → cert-manager
         → flux-operator → flux-instance (+ kube-prometheus-stack CRDs)
          └─ FluxInstance syncs github.com/D-o-c-labs/Doc-Home-ops@main
             path kubernetes/flux/cluster
              ├─ Kustomization flux-repositories → kubernetes/flux/repositories (bjw-s HelmRepository)
              └─ Kustomization cluster-apps (sops-age decryption) → kubernetes/apps
                  └─ apps/<ns>/kustomization.yaml (namespace + flux/alerts components)
                      └─ apps/<ns>/<app>/ks.yaml (Flux Kustomization per stack)
                          └─ apps/<ns>/<app>/app/ (HelmRelease, ExternalSecret, netpol, ...)
```

## Stack contract

- `ks.yaml`: Flux Kustomization(s), `dependsOn`, `components`, `postBuild.substitute` (`APP`, `HOSTNAME`, `VOLSYNC_*`, `APP_UID/GID`).
- `app/`: `helmrelease.yaml` (bjw-s app-template via `bjw-s-labs` HelmRepository, or upstream chart via a local `ocirepository.yaml`), `externalsecret.yaml`, `networkpolicy.yaml`, `kustomization.yaml`.
- Namespace inherited via `components/replacements/ks.yaml`; never set `metadata.namespace` in `ks.yaml`.
- Reference stack: `kubernetes/apps/selfhosted/n8n/`.

## Shared components (kubernetes/components)

| Component      | Adds                                                               |
| -------------- | ------------------------------------------------------------------ |
| `namespace`    | Namespace object                                                   |
| `flux/alerts`  | Flux `Alert` + `Provider`                                          |
| `flux/sops`    | `sops-age` secret                                                  |
| `replacements` | Copies namespace into child Flux Kustomizations                    |
| `volsync`      | PVC + Wasabi restic ReplicationSource/Destination + ExternalSecret |

## Cross-cutting

- Secrets: 1Password → onepassword-connect → ClusterSecretStore `onepassword` → ExternalSecret. Postgres creds: store `crunchy-pgo-secrets`. Git-stored secrets: `*.sops.yaml` (age).
- Network policy: label-driven Cilium clusterwide policies in `kubernetes/apps/kube-system/cilium/netpols/` (see `network.md`).
- Upgrades: Renovate (`renovate.json5`, `.renovate/`) for images/charts; tuppr for Talos/Kubernetes in-cluster.
- Ops entrypoint: `.justfile` modules → `kubernetes/{bootstrap,flux,talos,volsync,postgres}/mod.just`, `kubernetes/mod.just` (k8s), `sops/mod.just`.

## Out-of-cluster

- External media VM `external-media.piscio.net` (192.168.32.202) and `external-library.piscio.net`: NFS for media apps.
- Synology NAS `piscionas.piscio.net` (192.168.32.201): NFS for downloads/media; currently down, dependent apps scaled to 0.
- Cloudflare: public DNS, tunnel (cloudflared), ACME DNS-01.
- OPNsense: internal DNS via external-dns webhook.
- Wasabi S3: VolSync restic repos and pgBackRest.

## Related codemaps

`apps.md` (stacks + dependsOn), `network.md` (ingress/DNS/policy), `data.md` (storage/backup/DB), `dependencies.md` (charts, external services, CI).
