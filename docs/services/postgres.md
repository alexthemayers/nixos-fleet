# PostgreSQL and PgBouncer Database Service Configuration

This document describes the deployment and configuration details of the **PostgreSQL** and **PgBouncer** services in the
`nixos-fleet` infrastructure.

## Overview

The database system provides structured relational storage for all services in the fleet. It is deployed on the
dedicated database node, **`xcloud-postgres`**.

## Networking and Ports

- **PostgreSQL Daemon (Internal)**: Listens on port **`5433`** (access restricted to localhost, local systemd peer user,
  or encrypted connections from the Tailscale subnet).
- **PgBouncer (External API)**: Listens on the standard port **`5432`** (accepts connections from the Tailscale network
  `100.64.0.0/10`).
- **Exporter**: Exposes prometheus metrics on `9187` (Postgres Exporter) and pgbouncer metrics.

## Secrets Management

Passwords for all database system roles are decrypted using SOPS under ownership `postgres` (mode `0400`):

- Role Passwords: `postgres/gitlab_password`, `vaultwarden_password`, `immich_password`, `grafana_password`,
  `keycloak_password`, `vikunja_password`, `coder_password`, `paperless_password`, and exporter passwords.
- `ssh_backup/privkey`: Private key used to sync SQL archives to `rpi4`.

## Memory (1 GiB hub)

`xcloud-postgres` is sized for 1 GiB RAM / 1 CPU
([ADR](../adr/2026-09-04-xcloud-postgres-1g.md)). Module:
[services/postgres.nix](../../services/postgres.nix).

PostgreSQL: `shared_buffers=128MB`, `work_mem=4MB`, `max_connections=70`,
JIT off. PgBouncer bounds backends; Attic session pooling stays at 20 so
fills do not `query_wait_timeout`. Alloy on this host is `MemoryMax=160M`
(fleet default 512M is for the obs VMs).

After switch, restart `postgresql.service` if it did not already (these
settings need a restart, not a reload). Confirm with `free -h` and:

```bash
sudo -u pgbouncer psql -h /run/pgbouncer -p 5432 -d pgbouncer -c 'SHOW POOLS;'
```

## PgBouncer Connection Pooling

PgBouncer is deployed in front of PostgreSQL to prevent connection
starvation and optimize memory overhead:

- **Default Mode**: Transaction pooling (`pool_mode = "transaction"`).
- **Exceptions**: Session pooling for Immich (`pool_size=8`), Coder (5),
  Vikunja (3), and Attic (20). Those clients use session-scoped features
  (advisory locks or sqlx prepared statements). `pool_size` must be set
  explicitly: it otherwise inherits `default_pool_size=4`, and Immich
  queued then `query_wait_timeout`. Attic's cap is 20 because atticd on
  proxmox-dev opens a sqlx pool of ~10; 5 caused `query_wait_timeout` on
  uploads. Do not cut Attic to save idle RAM; fill spikes may use zram.
- **Idle servers**: `server_idle_timeout=60` so auth_query and unused
  transaction-mode backends do not sit for days. That timeout does not
  drop a server assigned to a session client.
- **Idle-in-transaction**: `idle_transaction_timeout=0`. A 120s timer
  closed Immich's advisory-lock sessions (`CONNECTION_CLOSED` every ~2
  minutes) and crash-looped `immich-server`. Grafana's idle-in-transaction
  pin is already capped by `pool_size=5`.
- **Dynamic Authentication**: `auth_type = "scram-sha-256"` and
  `auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1"`.
  PgBouncer queries PostgreSQL for passwords instead of a static file.
  The `postgres` database pool is 2 (auth_query + exporter).
  Named databases set `max_db_connections` to the same number as
  `pool_size` so the exporter does not report `max_connections=0`.

## Custom Setup & Immich Vector Extensions

PostgreSQL runs version **17** with vector extensions `pgvector` and `vectorchord` preloaded:

- **Bootstrap Service**: A oneshot systemd service (`postgresql-custom-setup`) runs after initialization:
    - It waits for databases to be ready.
    - Generates extensions for the `immich` database: `unaccent`, `uuid-ossp`, `cube`, `earthdistance`, `pg_trgm`,
      `vector`, and `vchord`.
    - Dynamically reads the sops-decrypted password files from `/run/secrets/` and runs SQL queries to set the passwords
      for each system role (`ALTER ROLE <name> WITH PASSWORD '<secret>';`). This keeps passwords out of the Nix store.

## Storage and Backups

- **Storage Layout**: Disk partitions are managed via Disko. The operating system runs on `/dev/vda` (20GB), while
  PostgreSQL's state `/var/lib/postgresql` is mapped to a dedicated block storage disk `/dev/vdb` (10GB) formatted as
  `ext4`.
- **JSON Log format**: PostgreSQL outputs logs in `jsonlog` format, stored at `/var/lib/postgresql/17/log/`. This allows
  Loki's Alloy collector to scrape and parse database logs easily.
- **Backups**:
    - The backup system runs daily at 02:00, creating full SQL dumps compressed via `zstd` at `/var/backup/postgresql/`.
    - **Sync**: After backups complete, the service runs `rsync` over SSH to copy the archives to
      `alex@rpi4:/mnt/usb-backup/postgres_backups/` using the decrypted private key.
    - **Verify then delete**: A second `rsync --checksum --dry-run` pass writes its itemised diff to
      `$RUNTIME_DIRECTORY/verify.txt`. Any output there fails the unit and the local archives are kept; only a clean
      pass reaches the `find -delete` that frees `/var/backup/postgresql`. `postStart` runs as `postgres`, so the
      scratch file must live under the unit's `RuntimeDirectory` — a plain `/run/...` path is not writable and fails
      the unit every night while leaving the archives to pile up.

## Alerting

Postgres and PgBouncer rules live in `postgres` and `pgbouncer` groups in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). The pool is
the real connection cliff; `PostgresTooManyConnections` watches the
backend.

| Alert | Catches |
|---|---|
| `PostgresTooManyConnections` | `pg_stat_activity` above 85% of max |
| `PostgresDeadlocksDetected` | deadlocks in 5m |
| `PostgresLowCacheHitRatio` | cache hit below 90% |
| `PgBouncerWaitingClients` | clients waiting on a pool |
| `PgBouncerPoolNearCapacity` | current / pool_size above 85% **and** waiting clients |
| `PgBouncerClientsNearMax` | client slots above 85% of 200 |
