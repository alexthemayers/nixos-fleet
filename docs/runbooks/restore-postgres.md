# Runbook: restore PostgreSQL

**Status:** documented, **not drill-tested** (2026-08-29).

This restores the fleet database on `xcloud-postgres` from a `postgresqlBackup`
dump. It is not a generation rollback — see
[rollback.md](rollback.md) for that.

## RPO and RTO

- **RPO:** last successful daily dump. The timer runs at 02:00, zstd-compresses
  every database, rsyncs off-host, checksum-verifies, then deletes the local
  copy. If the off-host target is unreachable, the unit fails and the dump
  stays on `xcloud-postgres` under `/var/backup/postgresql` only until the
  next successful run deletes it.
- **Temporary reroute (since 2026-09-07):** `rpi4` is offline; the off-host
  target is `backup-relay@proxmox-dev:/var/backup-relay/postgres_backups/`
  instead of `rpi4`, per
  [`fleet-simplification-migration.md`](fleet-simplification-migration.md)
  Step 2. `services/postgres.nix` has the current target in a `backupTarget`
  let-binding at the top of the file — check that, not this doc, for the
  live value. Revert this doc's "Where the files are" section below once
  `rpi4` is back.
- **RTO:** untested. Expect an hour-scale outage: stop consumers, restore,
  start consumers, check Keycloak/GitLab/Grafana. This is not an SLA.

`rpi4` has been unreachable for several days at a time. Treat "the USB disk
holds last night's dump" as **unconfirmed** until you can SSH to the Pi and
`ls` the files.

## Where the files are

- Live dumps (briefly): `xcloud-postgres:/var/backup/postgresql/all_*.sql.zstd`
- Off-host: `rpi4:/mnt/usb-backup/postgres_backups/` — **temporarily**
  `proxmox-dev:/var/backup-relay/postgres_backups/` while `rpi4` is down (see
  above)
- Postgres itself listens on **5433**. Port **5432** is PgBouncer. Restore
  through 5433. Connecting to 5432 during an incident debugs the wrong daemon.

Immich (and any other app whose files live on NFS) is **not** reconstituted by
this dump alone. Restore the database, then confirm the matching TrueNAS
dataset is intact.

## Restore (outline)

Do this from a console or `root@xcloud-postgres` session that will survive
the database restart. Take a fresh dump first if the VM still starts.

1. Stop application writers (Keycloak, GitLab, Grafana, Immich, Paperless,
   Vikunja, Coder, Vaultwarden, Attic). Leaving them up means they reconnect
   mid-restore and write into a half-loaded catalog.
2. Copy the chosen `all_<timestamp>.sql.zstd` onto `xcloud-postgres`.
3. Stop PgBouncer, then Postgres.
4. Empty or move aside `/var/lib/postgresql/17` (this is destructive).
5. Start Postgres only. It will come up empty and run `ensureDatabases`.
6. `zstd -d -c all_<timestamp>.sql.zstd | psql -p 5433 -d postgres`
7. Run `postgresql-custom-setup` (or reboot) so role passwords from sops match
   what the apps expect.
8. Start PgBouncer, then the apps. Check
   `psql -p 5433 -c 'select datname from pg_database;'` and one app login.

Do **not** point `psql` at 5432 for this. PgBouncer cannot run the restore.

## What this does not restore

- Immich originals and thumbnails (NFS).
- GitLab repositories, registry blobs, and the GitLab backup tarball — see
  [restore-gitlab.md](restore-gitlab.md).
- Garage object storage (Loki/Mimir/Attic).
