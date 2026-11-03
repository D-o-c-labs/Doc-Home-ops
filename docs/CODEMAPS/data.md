<!-- Generated: 2026-11-03 | Files scanned: 38 (storage, database, volsync, components) | Token estimate: ~650 -->

# Data and Storage

## Storage classes

| Class              | Backend                                           | Use                               |
| ------------------ | ------------------------------------------------- | --------------------------------- |
| `ceph-block`       | Rook Ceph RBD (default)                           | app config PVCs, VolSync restores |
| `ceph-filesystem`  | Rook CephFS                                       | shared RWX                        |
| `openebs-hostpath` | OpenEBS local PV under `/var/mnt/extra`           | VolSync cache, local scratch      |
| NFS (inline)       | `piscionas`, `external-media`, `external-library` | media libraries and downloads     |

- Snapshot classes: `csi-ceph-blockpool` (VolSync source), `openebs-hostpath` (cache); snapshot-controller in `system-controllers`.

## VolSync (per-app backups)

```text
ks.yaml components: [../../../../components/volsync]
  → PVC ${VOLSYNC_CLAIM:-${APP}} (ceph-block, ${VOLSYNC_CAPACITY:-1Gi})
  → ReplicationSource ${APP}-wasabi  (restic, cron "0 1 * * *")
  → ReplicationDestination ${APP}-bootstrap (populates a new PVC from the latest snapshot)
  → ExternalSecret ${APP}-volsync-wasabi (1Password → restic repo + Wasabi creds)
```

- Vars: `VOLSYNC_CLAIM`, `VOLSYNC_CAPACITY`, `VOLSYNC_CACHE_CAPACITY`, `VOLSYNC_STORAGECLASS`, `VOLSYNC_SNAPSHOTCLASS`, `VOLSYNC_ACCESSMODES`, `APP_UID/APP_GID` (default 2000).
- Ops: `just volsync list|snapshot|snapshot-all|restore|unlock` (`kubernetes/volsync/mod.just`, templates in `kubernetes/volsync/templates/`). `restore` `previous` = number of snapshots to skip (0 = latest).

## Postgres (Crunchy PGO)

- `PostgresCluster` `postgres` in ns `database`, Postgres 16, 2 instances, PgBouncer x2.
- Backups: pgBackRest `repo1` → Wasabi bucket `doc-pgo`.
- Users/DBs declared in `spec.users`; app credentials published to ClusterSecretStore `crunchy-pgo-secrets`; `crunchy-userinit-controller` initialises per-user DBs.
- Access requires pod label `egress.home.arpa/postgres-cluster: allow`.
- pgAdmin scaled on demand: `just postgres pgadmin`.
- Dump/restore: `just postgres crunchy-dump <db> [dir]`, `crunchy-restore <db> <user> <file>`.

## Other stateful services

- EMQX (MQTT) operator + cluster in `database` → zigbee2mqtt.
- ghostfolio-redis (in `selfhosted/ghostfolio`).
- VictoriaLogs (logs), kube-prometheus-stack Prometheus (metrics).
