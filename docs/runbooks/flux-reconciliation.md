# Runbook: Flux Reconciliation

Use this runbook when workloads are not converging to the desired Git state.

## Symptoms

- `HelmRelease` or `Kustomization` stays `NotReady`.
- New commit merged, but resources are not updated.
- Drift appears between cluster resources and repository manifests.

## Quick checks

```bash
kubectl get kustomizations -A
kubectl get helmreleases -A
flux get sources git -A
```

Review controller logs:

```bash
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller
```

## Recovery actions

Sync all Kustomizations using current source revision:

```bash
just k8s sync-all-ks
```

Force full source refresh and reconcile for a specific stack:

```bash
just k8s reconcile-ks namespace=selfhosted name=n8n
```

Force full reconcile for HelmRelease:

```bash
just k8s reconcile-hr namespace=selfhosted name=n8n
```

## Verification

1. `flux get kustomizations -A` reports `Ready=True`.
2. `flux get helmreleases -A` reports desired revision.
3. Target workload pods are healthy and on expected image/chart versions.
