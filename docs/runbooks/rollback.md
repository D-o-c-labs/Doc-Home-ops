# Runbook: Rollback

Use this runbook to recover from a failed rollout.

## Strategy

Git is the primary rollback mechanism. Revert the commit that introduced the failure and let Flux reconcile back to the previous desired state.

## Steps

1. Identify the breaking commit in `main`.
1. Revert it in a new commit:

```bash
git revert <commit-sha>
git push origin main
```

1. Force reconcile if needed:

```bash
just k8s reconcile-all-ks
just k8s reconcile-all-hr
```

## Stateful workloads

If data corruption or schema mismatch occurred, perform targeted restore after config rollback:

```bash
just volsync list app=<app> ns=<namespace>
just volsync restore app=<app> ns=<namespace> previous=<snapshot-timestamp>
```

For Crunchy Postgres:

```bash
just postgres crunchy-dump db_name=<db> ns=<namespace>
just postgres crunchy-restore db_name=<db> db_user=<user> file=<backup-file>
```

## Verification

1. `flux get` status returns healthy.
1. Application endpoints and probes are green.
1. Logs show no repeating startup or dependency errors.
