# Observability Stack

The `observability` namespace replaces the former `monitoring` namespace and aligns with bjw-s conventions while preserving local requirements.

## Components

- **kube-prometheus-stack**: Deploys Prometheus, Alertmanager, and CRDs with in-cluster CRD management enabled. Routes are published via `envoy-internal`, with hostnames injected through Flux `postBuild` substitutions.
- **Grafana**: Retains Authentik OAuth, VolSync-backed persistence, and now consumes Prometheus, Alertmanager, and VictoriaLogs datasources from the `observability` namespace.
- **Exporters**: `blackbox-exporter`, `node-exporter`, `kube-state-metrics`, and `kromgo` follow bjw-s values while keeping Piscio-specific ServiceMonitor targets and route host substitutions.
- **Logging**: `victoria-logs` provides log storage, and `fluent-bit` forwards container logs via HTTP to the VictoriaLogs server.
- **Storage health**: `smartctl-exporter` scrapes SMART metrics across nodes for disk visibility.
- **Alert hygiene**: `silence-operator` handles declarative silences; add silence manifests under `kubernetes/apps/observability/silence-operator/silences/` as needed.

## Flux Recipes

Render the namespace locally before committing changes:

```bash
just k8s render-local-ks observability observability
```

Apply a single Kustomization after review:

```bash
just k8s apply-ks observability observability
```

## Follow-up

- Ensure any workloads referencing `monitoring.svc.cluster.local` update to `observability.svc.cluster.local`.
- Add new silences deliberately; the default `silences` Kustomization ships empty.
- Provision the required 1Password secrets (`alertmanager-secret`, Grafana OAuth credentials) before applying.
