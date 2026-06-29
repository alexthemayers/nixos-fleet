# PostgreSQL and PgBouncer Database Service Configuration

This document describes the deployment and configuration details of the **PostgreSQL** and **PgBouncer** services in the `nixos-fleet` infrastructure.

## Overview
The database system provides structured relational storage for all services in the fleet. It is deployed on the dedicated database node, **`xcloud-postgres`**.

## Networking and Ports
- **PostgreSQL Daemon (Internal)**: Listens on port **`5433`** (access restricted to localhost, local systemd peer user, or encrypted connections from the Tailscale subnet).
- **PgBouncer (External API)**: Listens on the standard port **`5432`** (accepts connections from the Tailscale network `100.64.0.0/10`).
- **Exporter**: Exposes prometheus metrics on `9187` (Postgres Exporter) and pgbouncer metrics.

## Secrets Management
Passwords for all database system roles are decrypted using SOPS under ownership `postgres` (mode `0400`):
- Role Passwords: `postgres/gitlab_password`, `vaultwarden_password`, `immich_password`, `grafana_password`, `keycloak_password`, `vikunja_password`, `coder_password`, `paperless_password`, and exporter passwords.
- `ssh_backup/privkey`: Private key used to sync SQL archives to `rpi4`.

## PgBouncer Connection Pooling
PgBouncer is deployed in front of PostgreSQL to prevent connection starvation and optimize memory overhead:
- **Default Mode**: Transaction pooling (`pool_mode = "transaction"`), allowing high concurrency.
- **Exceptions**: Session pooling (`pool_mode = "session"`) is forced for Immich (max 30 connections) and Coder (max 5 connections) as they rely on session locks.
- **Dynamic Authentication**: Configured with `auth_type = "scram-sha-256"` and `auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1"`. Instead of maintaining database user passwords in static configuration files, PgBouncer queries PostgreSQL directly to authenticate incoming client connection passwords dynamically.

## Custom Setup & Immich Vector Extensions
PostgreSQL runs version **17** with vector extensions `pgvector` and `vectorchord` preloaded:
- **Bootstrap Service**: A oneshot systemd service (`postgresql-custom-setup`) runs after initialization:
  - It waits for databases to be ready.
  - Generates extensions for the `immich` database: `unaccent`, `uuid-ossp`, `cube`, `earthdistance`, `pg_trgm`, `vector`, and `vchord`.
  - Dynamically reads the sops-decrypted password files from `/run/secrets/` and runs SQL queries to set the passwords for each system role (`ALTER ROLE <name> WITH PASSWORD '<secret>';`). This keeps passwords out of the Nix store.

## Storage and Backups
- **Storage Layout**: Disk partitions are managed via Disko. The operating system runs on `/dev/vda` (20GB), while PostgreSQL's state `/var/lib/postgresql` is mapped to a dedicated block storage disk `/dev/vdb` (10GB) formatted as `ext4`.
- **JSON Log format**: PostgreSQL outputs logs in `jsonlog` format, stored at `/var/lib/postgresql/17/log/`. This allows Loki's Alloy collector to scrape and parse database logs easily.
- **Backups**:
  - The backup system runs daily at 02:00, creating full SQL dumps compressed via `zstd` at `/var/backup/postgresql/`.
  - **Sync**: After backups complete, the service runs `rsync` over SSH to copy the archives to `alex@rpi4:/mnt/usb-backup/postgres_backups/` using the decrypted private key.
