# Garage S3 Object Storage Service Configuration

This document describes the deployment and configuration details of the **Garage S3 Object Storage** service in the
`nixos-fleet` infrastructure.

## Overview

Garage is a lightweight, distributed S3-compatible object store. In this fleet, it is deployed as a replicated cluster
across **`proxmox-db-1`**, **`proxmox-db-2`**, and **`rpi4`** to provide high-availability storage.

## Networking and Ports

Garage utilizes three ports, allowed on the Tailscale firewall:

- **`3901`**: RPC port for inter-node communication (gossip mesh).
- **`3902`**: S3 API endpoint (`*.s3.alexmayers.co.za`).
- **`3903`**: Admin API endpoint (used by the bootstrap daemon).

## Secrets Management

- **`garage/rpc_secret`**: Secret key used for secure node authentication.
- **`garage/admin_token`**: Token used to authorize CLI admin commands.

These are written directly to environment variables `GARAGE_RPC_SECRET_FILE` and `GARAGE_ADMIN_TOKEN_FILE` using SOPS
integration.

## Storage and Clustering

- **Replication**: Configured with a `replication_factor = 2`, meaning all data is replicated across the cluster (
  `proxmox-db-1`, `proxmox-db-2`, and `rpi4`).
- **Database Engine**: Uses the `sqlite` database engine to keep track of block metadata.
- **Storage Locations**:
    - `proxmox-db-1`, `proxmox-db-2`: NFS mount `truenas-scale:/mnt/ssd/garage/data` is mounted to
      `/mnt/nfs/garage/data` (relies on
      `fleet.waitForHost` targeting `truenas-scale`).
    - `rpi4`: Data is stored locally on SD card / disk at `/var/lib/garage/data`.

## Bootstrapping and Key Management

To automate S3 setup, a custom oneshot systemd service (`garage-bootstrap`) runs strictly on **`proxmox-db-1`**:

1. It waits for the local S3 daemon to come online.
2. Creates keys inside `/var/lib/garage/keys/`.
3. Creates three core S3 buckets:
    - **`loki`** (used for system logs storage)
    - **`mimir`** (used for system metrics database blocks)
    - **`web-assets`** (for generic static assets)
4. Configures permissions linking the generated keys to the respective buckets with read-write access.
