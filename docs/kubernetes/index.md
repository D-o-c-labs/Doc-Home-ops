# Kubernetes Overview

Kubernetes workloads and infrastructure are fully GitOps-managed with Flux. The repository drives reconciliation of app stacks, shared components, and cluster controllers.

## GitOps flow

1. Flux watches this repository for changes.
2. Flux renders Kustomizations and HelmReleases.
3. Desired state is applied to the cluster continuously.
4. Drift is corrected by the reconciliation loop.

## Repository layout

- `kubernetes/apps/`: domain-scoped app and controller stacks.
- `kubernetes/components/`: reusable overlays and shared components.
- `kubernetes/bootstrap/`: bootstrap Helmfile and foundational setup.
- `kubernetes/flux/`: Flux `GitRepository` and `Kustomization` resources.

## Secrets and credentials

- `ExternalSecret` resources pull runtime secrets from 1Password.
- SOPS with age protects encrypted secret files in Git.
- Secret rotation uses `just sops re-encrypt` and External Secrets sync.

## Common commands

Render a stack locally:

```bash
just flux build-ks dir=selfhosted/n8n
```

Apply one stack:

```bash
just flux apply-ks dir=selfhosted/n8n
```

Force full reconcile for one Kustomization:

```bash
just k8s reconcile-ks namespace=selfhosted name=n8n
```

## Related pages

- [Applications](apps/index.md)
- [Infrastructure](infrastructure/index.md)
