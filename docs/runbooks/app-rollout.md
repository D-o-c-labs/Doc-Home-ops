# Runbook: App Rollout

Use this runbook to deploy a new application stack in the GitOps workflow.

## Prerequisites

- Target domain chosen under `kubernetes/apps/<domain>/`.
- Secrets source identified in 1Password for `ExternalSecret`.
- Cilium policy requirements identified.

## Steps

1. Create stack directory:

```bash
mkdir -p kubernetes/apps/<domain>/<app>/app
```

1. Add stack files:

- `kustomization.yaml`
- `ks.yaml`
- `app/helmrelease.yaml`
- Optional: `app/externalsecret.yaml`, `app/networkpolicy.yaml`, PVC manifests

1. Add stack reference to the parent `kustomization.yaml` in the domain.

1. Render and validate:

```bash
just flux build-ks dir=<domain>/<app>
```

1. Apply for immediate reconcile (optional in PR flow):

```bash
just flux apply-ks dir=<domain>/<app>
```

1. Run repository checks:

```bash
pre-commit run -a
```

## Post-deploy checks

```bash
kubectl get pods -n <domain>
kubectl get helmrelease -n <domain> <app>
kubectl get externalsecret -n <domain>
```

Confirm ingress, health checks, and any dependent service connectivity.
