# Runbook: Backup and Restore

This runbook covers snapshot-based recovery for stateful workloads.

## VolSync snapshots

List available snapshots:

```bash
just volsync list app=<app> ns=<namespace>
```

Create a snapshot:

```bash
just volsync snapshot app=<app> ns=<namespace> wait=true
```

Create snapshots for all replication sources:

```bash
just volsync snapshot-all
```

Restore from snapshot:

```bash
just volsync restore app=<app> ns=<namespace> previous=<snapshot-timestamp>
```

## Postgres dump and restore

Dump a database from Crunchy Postgres:

```bash
just postgres crunchy-dump db_name=<db> ns=<namespace>
```

Restore a dump:

```bash
just postgres crunchy-restore db_name=<db> db_user=<user> file=<backup-file>
```

## Validation

1. Check pod readiness and application health endpoints.
2. Verify expected data is present.
3. Run a targeted smoke test for app functionality.
