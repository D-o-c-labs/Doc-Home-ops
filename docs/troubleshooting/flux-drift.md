# Troubleshooting: Flux Drift

Drift means cluster state does not match desired Git state.

## Typical causes

- Reconciliation suspended.
- Source fetch errors.
- Kustomize/Helm render failures.
- Manual cluster changes outside GitOps flow.

## Diagnose

```bash
flux get kustomizations -A
flux get helmreleases -A
flux get sources git -A
```

Check resource history:

```bash
kubectl describe kustomization <name> -n <namespace>
kubectl describe helmrelease <name> -n <namespace>
```

## Fix

1. Ensure source repository is ready.
2. Reconcile affected Kustomizations and HelmReleases.
3. Remove manual mutations and commit desired changes to Git.
4. Verify `Ready=True` and expected revision.

## Prevention

- Avoid manual `kubectl edit/apply` for managed resources.
- Keep each PR scoped and reviewed.
- Run `just flux build-ks` before merge.
