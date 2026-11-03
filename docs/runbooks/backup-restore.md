# Runbook: Backup and Restore

This runbook covers snapshot-based recovery for stateful workloads.

## VolSync snapshots

Arguments are positional (`app`, then the namespace, which defaults to `default`).

List available snapshots:

```bash
just volsync list <app> <namespace>
```

Create a snapshot:

```bash
just volsync snapshot <app> <namespace>
```

Create snapshots for all replication sources:

```bash
just volsync snapshot-all
```

Restore from snapshot. `previous` is how many snapshots to skip back (`0` = latest, `1` = the one before):

```bash
just volsync restore <app> <previous> <namespace>
```

## Postgres dump and restore

Dump a database from Crunchy Postgres:

Arguments are positional; the namespace and cluster default to `database`/`postgres`. The dump is written as `<output_dir>/<db>.psql` with mode 600 because it contains credentials and secrets.

```bash
just postgres crunchy-dump <db> [output_dir]
```

Restore a dump:

```bash
just postgres crunchy-restore <db> <user> <backup-file>
```

## Validation

1. Check pod readiness and application health endpoints.
2. Verify expected data is present.
3. Run a targeted smoke test for app functionality.
