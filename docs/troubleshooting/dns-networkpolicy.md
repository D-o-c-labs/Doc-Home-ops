# Troubleshooting: DNS and NetworkPolicy

Use this guide when workloads cannot resolve names or reach required services.

## Symptoms

- DNS lookup failures in pods.
- Timeouts connecting to services in other namespaces.
- Internet or LAN egress blocked unexpectedly.

## DNS checks

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system deploy/coredns
```

Run a quick DNS test pod:

```bash
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```

## Network policy checks

1. Confirm required Cilium labels are present on the workload pods.
2. Verify matching clusterwide policy intent in `kubernetes/apps/kube-system/cilium/netpols/`.
3. Inspect service-specific `app/networkpolicy.yaml` if used.

List network policies:

```bash
kubectl get ciliumclusterwidenetworkpolicies
kubectl get ciliumnetworkpolicies -A
```

## Common fixes

- Add missing `egress.home.arpa/kubedns: allow`.
- Add required ingress/egress labels for gateway, LAN, internet, or SSO access.
- Update both source and destination policies for cross-namespace traffic.

## Validation

Repeat DNS and connectivity checks from the affected pod after policy updates and Flux reconciliation.
