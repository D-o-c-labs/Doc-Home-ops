# Troubleshooting: HelmRelease Failures

Use this guide when a HelmRelease remains not ready or repeatedly retries.

## Diagnose quickly

```bash
kubectl get helmrelease -A
kubectl describe helmrelease <name> -n <namespace>
kubectl get pods -n <namespace>
```

Inspect helm-controller logs:

```bash
kubectl logs -n flux-system deploy/helm-controller
```

## Common failure patterns

- Chart source unavailable or auth failure.
- Invalid values after chart update.
- Missing secrets referenced by environment variables.
- Conflicts with immutable Kubernetes fields.
- Network policy blocking required dependencies.

## Recovery steps

1. Confirm chart/source availability.
1. Validate values in `app/helmrelease.yaml`.
1. Ensure required `ExternalSecret` and generated `Secret` exist.
1. Reconcile with source refresh:

```bash
just k8s reconcile-hr namespace=<namespace> name=<release>
```

1. If change is unsafe, revert commit and let Flux roll back desired state.

## Verification

- HelmRelease `Ready=True`.
- Pods are healthy and not crash looping.
- Endpoint probes and dependencies are reachable.
