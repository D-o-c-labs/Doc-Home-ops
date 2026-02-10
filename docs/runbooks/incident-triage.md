# Runbook: Incident Triage

Use this checklist for a fast, consistent first response to incidents.

## 1. Establish cluster health

```bash
kubectl get nodes
kubectl get pods -A | grep -E 'CrashLoopBackOff|Error|Pending'
kubectl get kustomizations -A
kubectl get helmreleases -A
```

## 2. Determine blast radius

- Which namespaces are affected?
- Is it control plane, networking, storage, or application-only?
- Is user traffic impacted or only background workloads?

## 3. Collect evidence

```bash
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

For Flux controller issues:

```bash
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller
```

## 4. Mitigate

- Reconcile affected resources.
- Roll back recent changes if needed.
- Restore from snapshots for stateful failures.

## 5. Closeout

1. Confirm recovery and service stability.
2. Document root cause and timeline.
3. Add preventive actions to backlog.
