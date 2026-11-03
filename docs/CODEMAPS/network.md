<!-- Generated: 2026-11-03 | Files scanned: 41 (network/, cilium/netpols, cert-manager) | Token estimate: ~700 -->

# Network

## Ingress paths

```text
Internet → Cloudflare (proxied *.piscio.net) → cloudflared tunnel
  → https://envoy-external.network.svc (SNI ingress-ext.piscio.net)
  → Gateway envoy-external (LB 192.168.32.152) → HTTPRoute → app Service

LAN → OPNsense DNS (per-route records → ingress-int.piscio.net)
  → Gateway envoy-internal (LB 192.168.32.151) → HTTPRoute → app Service
```

- Gateways: `kubernetes/apps/network/envoy-gateway/config/{external,internal,envoy}.yaml`.
- TLS: wildcard Certificate `*.piscio.net` + `piscio.net` (`config/certificate.yaml`), issued by `letsencrypt-production` (DNS-01 via Cloudflare token). `letsencrypt-staging` also defined.
- Apps opt in with app-template `route:` and `parentRefs: [{name: envoy-external|envoy-internal, namespace: network}]`.
- LB IPs: Cilium LB-IPAM via `lbipam.cilium.io/ips` annotation.

## DNS

| Instance               | Provider                               | Sources                    | Scope                                       |
| ---------------------- | -------------------------------------- | -------------------------- | ------------------------------------------- |
| externaldns-cloudflare | cloudflare (proxied)                   | gateway-httproute, crd     | routes on `envoy-external` + `DNSEndpoint`s |
| externaldns-internal   | webhook (OPNsense, crutonjohn webhook) | gateway-httproute, service | all routes + services, domain `piscio.net`  |

- Cluster DNS: CoreDNS (`kube-system/coredns`).
- cloudflared `DNSEndpoint` (`network/cloudflared/app/dnsEndpoint.yaml`): `ingress-ext.piscio.net` CNAME → `<tunnel-id>.cfargotunnel.com`.

## Pod networking

- CNI: Cilium (`kube-system/cilium`), kube-proxy replacement; no Flannel/kube-proxy on Talos.
- Multus (`network/multus`) adds the `iot` network (`networks/iot.yaml`) to esphome and home-assistant.
- Talos nodes carry a VLAN 40 (`192.168.40.0/24`, "domus") address per node (`topf.yaml` `domusAddress`).

## Cilium policy model

Label pods with `<direction>.home.arpa/<target>: allow`; clusterwide policies live in `kubernetes/apps/kube-system/cilium/netpols/`.

- Egress: `kubedns`, `internet`, `world`, `lan`, `domus-vlan`, `synology`, `external-media`, `apiserver`, `envoy-internal`, `sso`, `postgres-cluster` (defined in `database/crunchy-postgres-operator/cluster/networkpolicy.yaml`).
- Ingress: `gateway-route`, `lan`, `metrics`, `internet`, `world`.
- Any `egress.home.arpa/*` label switches the pod to egress default-deny, so `egress.home.arpa/kubedns` is always required.
- Per-app `app/networkpolicy.yaml` only for tighter port/CIDR scope or cross-namespace pairs.

## Notable consumers

- `sso` (Authentik): cloudflared, actual-budget, mealie, metamcp, splitpro.
- `postgres-cluster`: autobrr, home-assistant, ghostfolio, mealie, metamcp, n8n, splitpro (+ mcpjungle, disabled).
- `external-media`: radarr, sonarr.
