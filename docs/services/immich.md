# Immich Service Configuration

This document describes the deployment and configuration details of the **Immich** service in the `nixos-fleet`
infrastructure.

## Overview

Immich is a high-performance self-hosted backup solution for photos and videos. It is deployed on the general
applications node, **`proxmox-applications-debian`**, which is specifically utilized for workloads requiring GPU hardware
acceleration.

## Networking and Ports

- **Internal Port**: `2283` (TCP)
- **Public Domain**: `https://immich.alexmayers.co.za` (reverse proxied via Caddy).
- **Log Format**: Environment variable `IMMICH_LOG_FORMAT` is forced to `json` for standardized log collection.

## Secrets Management

- **`immich/env`**: Decrypted by SOPS and loaded as the environment secrets file for database credentials, mapbox keys,
  and other application secrets.

## Database Integration

Immich connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `immich`
- **Port**: `5432` (PgBouncer)
- **Pool Mode**: Connection is forced to **session** pooling mode in PgBouncer
  configs (`pool_size=16`, `max_db_connections=16`). Immich API plus
  microservices open ~10 postgres.js connections each. At 8, upload bursts
  waited 120s, hit `query_wait_timeout`, and the worker exited with
  `CONNECTION_CLOSED` — Caddy then 502'd until `immich-server` came back.
- **Custom PostgreSQL Setup**: Immich requires extensive vector operations. A oneshot systemd service (
  `postgresql-custom-setup`) runs on `xcloud-postgres` to initialize schema ownership and create required PostgreSQL
  extensions: `unaccent`, `uuid-ossp`, `cube`, `earthdistance`, `pg_trgm`, `vector` (pgvector), and `vchord` (
  vectorchord).

## Storage and Mounts

Immich stores photos and machine learning caches on the TrueNAS NAS:

- **NFS Photo Mount**: `truenas-scale:/mnt/hdd/photos` is mounted to `/mnt/nfs/immich/photos`.
- **NFS Model Cache Mount**: `truenas-scale:/mnt/ssd/immich/model-cache` is mounted to `/mnt/nfs/immich/model-cache`.
- **Systemd Mount Guards**: Mounts are declared as `noauto` and rely on `wait-for-host-immich.service` targeting the NAS
  hostname to prevent boot hangs.
- **Service Sandboxing**: Systemd configurations overlay the server and machine-learning services, using `BindPaths` to
  map the NFS paths into the private local directories:
    - `immich-server` binds NFS photos to `/var/lib/immich/photos`.
    - `immich-machine-learning` binds NFS model cache to `/var/lib/immich/model-cache`.

## Graphics Hardware Acceleration

To perform efficient image transcoding and video processing:

- **Drivers**: The system configures Intel hardware graphics (`hardware.graphics`) with the compute, media, and VAAPI
  runtime packages:
  ```nix
  extraPackages = with pkgs; [
    intel-media-driver
    intel-compute-runtime
    intel-vaapi-driver
  ];
  ```
- **Device Access**: The `immich` system user is added to `video` and `render`
  groups. `immich-server` maps `/dev/dri/renderD128` for VAAPI transcode.
  `immich-machine-learning` does **not**: OpenVINO on this Xe fails to
  compile (`OpenVINO-EP` 500s on OCR and face jobs) and gunicorn then
  SIGINTs the worker. ML runs CPU (`PrivateDevices`, no DRI bind).
- **HEIC**: Sharp 0.35.5 needs libvips 8.18.7 or newer. Its prebuilt
  libvips has HEVC compiled out, so iPhone HEIC thumbnails fail. The
  guest builds libvips 8.18.7 against Debian's shared libheif, which
  loads `libheif-plugin-libde265`. `pkg-config --modversion vips` must
  stay at 8.18.7 so the next Immich build uses that library.

## Alerting

Rules in the `caddy` and `pgbouncer` groups in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). Dashboard:
Grafana folder `fleet`, `fleet-immich`.

| Alert | Catches |
|---|---|
| `ImmichEdge502` | more than ten Caddy 502s in 5m for `immich.alexmayers.co.za` |
| `PgBouncerWaitingClients` | clients waiting on a pool for 1m (was 5m; Immich dies at 120s) |
| `ServiceCrashLooping` | `immich-server` restarting |

Edge Caddy retries the upstream for 45s (`lb_try_duration`) so a
single `immich-server` restart does not immediately 502. Do not add a
Caddy `health_uri` here: marking the only upstream unhealthy 502s
every request (same lesson as Keycloak `/token`).
