# Talos Overview

Talos is the operating system layer for the cluster. Node state is managed declaratively and applied through Talos APIs rather than imperative SSH workflows.

## Why Talos

- Immutable and API-driven operations.
- Predictable upgrades and rollbacks.
- Strong fit for GitOps where machine configuration is code-reviewed.

## Source of truth

Machine configs are assembled by [topf](https://postfinance.github.io/topf/) from the files in `kubernetes/talos/`:

- `topf.yaml`: cluster name, endpoint, Talos and Kubernetes versions, and the nodes with their per-node data (install disk, VLAN 40 address).
- `schematic.yaml`: Image Factory schematic (kernel args and system extensions); topf derives the installer image from it and `talosVersion`.
- `all/`, `control-plane/`: strategic merge patches, applied in that order and alphabetically within each directory. Files ending in `.yaml.tpl` are Go templates (`.Node.Host`, `.Node.Data.<key>`, `.Data.<key>`).
- `secrets.sh`: topf's secrets provider. It renders `secrets.yaml.tpl` with the 1Password references in `secrets.env`, so the bundle never touches disk.

The patches use the Talos 1.14 config documents (`KubeAPIServerConfig`, `ResolverConfig`, `SysctlConfig`, ...). Only fields without a document stay in v1alpha1: `machine.certSANs`, `cluster.etcd`, and the whole kubelet (`KubeletConfig` has no `extraMounts`, which the openebs-hostpath local PVs under `/var/mnt/extra` need).

topf renders with the contract of the Talos version each node runs, so Talos 1.14 defaults appear in every config. The patches pin the ones that would change the nodes: no Flannel, CoreDNS, kube-proxy, PodSecurity admission or control-plane taint, and `workloadIsolation`/secure `/var` mount options stay off.

## Common operations

Show what would change on the running nodes:

```bash
just talos diff
```

Apply to every node, or to one (topf shows the diff and asks first):

```bash
just talos apply
just talos apply-node zeus
```

Inspect the merged configs (plaintext secrets, delete afterwards):

```bash
just talos render
```

Upgrade a node by hand (tuppr drives upgrades in-cluster):

```bash
just talos upgrade-node zeus
```

Upgrade Kubernetes control plane version:

```bash
just talos upgrade-k8s version=1.30.2
```

## Change checklist

1. Edit the patch or `topf.yaml`.
2. Review the change with `just talos diff`.
3. Apply one node at a time with `just talos apply-node <node>`.
4. Verify node health and Kubernetes readiness.
