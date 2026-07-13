# Immich Service Configuration

This document describes the deployment and configuration details of the **Immich** service in the `nixos-fleet`
infrastructure.

## Overview

Immich is a high-performance self-hosted backup solution for photos and videos. It is deployed on the general
applications node, **`proxmox-applications-1`**, which is specifically utilized for workloads requiring GPU hardware
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
- **Pool Mode**: Connection is forced to **session** pooling mode in PgBouncer configs.
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

To perform efficient image transcoding, video processing, and machine learning:

- **Drivers**: The system configures Intel hardware graphics (`hardware.graphics`) with the compute, media, and VAAPI
  runtime packages:
  ```nix
  extraPackages = with pkgs; [
    intel-media-driver
    intel-compute-runtime
    intel-vaapi-driver
  ];
  ```
- **Device Access**: The `immich` system user is added to `video` and `render` groups, and the service maps the
  rendering device `/dev/dri/renderD128` directly:
  ```nix
  accelerationDevices = [ "/dev/dri/renderD128" ];
  ```
