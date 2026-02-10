# Talos Overview

Talos is the operating system layer for the cluster. Node state is managed declaratively and applied through Talos APIs rather than imperative SSH workflows.

## Why Talos

- Immutable and API-driven operations.
- Predictable upgrades and rollbacks.
- Strong fit for GitOps where machine configuration is code-reviewed.

## Source of truth

- `kubernetes/talos/talconfig.yaml`: cluster intent and node topology.
- `kubernetes/talos/clusterconfig/`: generated machine configs.
- `kubernetes/talos/talhelper-secrets.env`: 1Password-backed secret mappings for rendering.

## Common operations

Generate machine configs:

```bash
just talos generate-clusterconfig
```

Dry-run apply to all nodes:

```bash
just talos apply-clusterconfig dry_run=true
```

Apply to a single node:

```bash
just talos apply-node node=zeus.piscio.net
```

Upgrade a node:

```bash
just talos upgrade-node node=zeus.piscio.net
```

Upgrade Kubernetes control plane version:

```bash
just talos upgrade-k8s version=1.30.2
```

## Change checklist

1. Update `talconfig.yaml`.
2. Generate `clusterconfig`.
3. Validate with dry-run apply.
4. Apply in controlled order.
5. Verify node health and Kubernetes readiness.
