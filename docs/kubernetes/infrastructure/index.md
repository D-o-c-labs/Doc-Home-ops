# Kubernetes Infrastructure

Infrastructure services provide networking, storage, observability, security, and controller primitives that every app stack depends on.

## Networking

- `kubernetes/apps/kube-system/cilium/`: CNI and policy enforcement.
- `kubernetes/apps/network/envoy-gateway/`: ingress and routing.
- `kubernetes/apps/network/cloudflared/`: edge connectivity.
- `kubernetes/apps/network/external-dns/`: DNS record automation.
- `kubernetes/apps/kube-system/coredns/`: cluster DNS.

## Storage and data protection

- `kubernetes/apps/openebs/openebs/` and `kubernetes/apps/rook-ceph/rook-ceph/`: storage backends.
- `kubernetes/apps/system/volsync/`: snapshot and restore workflows.
- PVC lifecycle and restore runbooks use `just volsync` recipes.

## Observability

- `kubernetes/apps/observability/kube-prometheus-stack/`: metrics and alerting.
- `kubernetes/apps/observability/grafana/`: dashboards.
- `kubernetes/apps/observability/fluent-bit/` and `victoria-logs/`: log collection and storage.
- Exporters: node, kube-state, blackbox, smartctl.

## Security and identity

- `kubernetes/apps/cert-manager/cert-manager/`: certificate automation.
- `kubernetes/apps/external-secrets/`: secret synchronization from 1Password.
- `kubernetes/apps/authentik/authentik/`: identity and SSO.

## System controllers

- `kubernetes/apps/flux-system/flux-operator/`: GitOps control plane.
- `kubernetes/apps/system/reloader/`: workload restarts on config changes.
- `kubernetes/apps/system/descheduler/`: pod placement balancing.
- `kubernetes/apps/system/node-feature-discovery/` and device plugins.
- `kubernetes/apps/system-upgrade/system-upgrade-controller/`: upgrade orchestration.
