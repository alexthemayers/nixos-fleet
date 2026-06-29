# Jellyfin Service Configuration

This document describes the deployment and configuration details of the **Jellyfin** service in the `nixos-fleet`
infrastructure.

## Overview

Jellyfin is a self-hosted media server that organizes and streams movie, show, and music assets. It is deployed on the
media node, **`proxmox-video`**.

## Networking and Ports

- **Ports**: Exposes standard media ports with firewall rules enabled.
- **Public Domain**: `https://jellyfin.alexmayers.co.za` (reverse proxied via Caddy).

## Storage and Mounts

Jellyfin mounts its media assets and configuration state from TrueNAS:

- **NFS Media Mount**: `truenas-scale:/mnt/hdd/media` is mounted to `/mnt/nfs/media`.
- **NFS Config Mount**: `truenas-scale:/mnt/ssd/jellyfin/config` is mounted to `/mnt/nfs/jellyfin/config`.
- **NFS Cache Mount**: `truenas-scale:/mnt/ssd/jellyfin/cache` is mounted to `/mnt/nfs/jellyfin/cache`.
- **Connectivity Guard**: Mounts use common options referencing oneshot wait service `jellyfin-wait-for-nas.service` to
  prevent boot degradation.
- **Systemd Overlay**: Systemd sandboxing restricts write permissions to the mounts using `BindPaths`:
    - NFS configuration binds to `/var/lib/jellyfin`.
    - NFS cache binds to `/var/lib/jellyfin/cache`.

## Graphics Hardware Acceleration

Jellyfin transcodes files on-the-fly using graphics adapters:

- **Drivers**: Configures hardware graphics with Intel media drivers, OpenCL compute runtime (critical for HDR to SDR
  tone mapping), and QuickSync Video (QSV) runtime for Arrow Lake architecture:
  ```nix
  extraPackages = with pkgs; [
    intel-media-driver
    intel-compute-runtime
    vpl-gpu-rt
  ];
  ```
- **Access**: Adds the `jellyfin` system user to the supplementary groups `render` and `video`.

## Key Configurations

- **JSON Logging Integration**: To allow Loki to ingest and parse Jellyfin logs, a custom Serilog configuration file (
  `logging.json`) is written to `/var/lib/jellyfin/config/logging.json` inside the `preStart` script, configuring
  console output to write logs in raw JSON format.
- **Stop Timeout Override**: Jellyfin can hang on service termination if threads fail to exit. To resolve this, the
  systemd service defines a stop timeout overlay:
  ```nix
  serviceConfig.TimeoutStopSec = "15s";
  ```
  This is marked in the code as "the silver bullet for the shutdown hang".
- **Restart Settings**: Configures service restart on-failure with a `10s` delay.
