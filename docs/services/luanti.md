# Luanti Game Server Service Configuration

This document describes the deployment and configuration details of the **Luanti** (formerly Minetest) game server
service in the `nixos-fleet` infrastructure.

## Overview

Luanti is an open-source voxel game engine. In this fleet, the game server is deployed on the general applications
node, **`proxmox-applications-1`**.

## Networking and Ports

- **Internal Port**: `30000` (UDP)
- **Public Access**: UDP traffic from the WAN is forwarded to the internal node over Caddy's Layer 4 proxy engine on
  port `30000`.
- **Firewall**: Allowed globally on the host's UDP port `30000`.

## Game Installation and preStart Scripts

The server is configured to run the **Mineclonia** game (a survival-focused voxel game). To automate game version
updates, the systemd unit runs a custom `preStart` script:

1. It checks if the game's configuration file `game.conf` exists at
   `/var/lib/minetest/.minetest/games/mineclonia/game.conf`.
2. If missing, it downloads the latest repository code from Codeberg using `curl`, extracts it into the target
   directory, and strips parent components:
   ```bash
   curl -sL https://codeberg.org/mineclonia/mineclonia/archive/main.tar.gz | gzip -d | tar -x -C /var/lib/minetest/.minetest/games/mineclonia --strip-components=1
   ```
3. Deletes translation files (`*.po`) inside the game directory to save storage space.

## Key Configurations

- **Game ID**: Configured to load `mineclonia` on startup.
- **Server Name**: Set default operator config name as `alex`.

## Storage and NFS Mounts

To ensure the persistent state of the Luanti game server (including worlds, configurations, and installed games) is
preserved across rebuilds, the server uses a dedicated NFS mount on TrueNAS:

- **NFS Share**: `truenas-scale:/mnt/ssd/luanti` is mounted to `/mnt/nfs/luanti`.
- **Connectivity Guard**: A systemd wait-for-host guard (`wait-for-host-luanti.service`) validates that the TrueNAS host
  is reachable before permitting mounting to prevent boot-time hangs.
- **Service Sandboxing**: The service's systemd configuration uses `BindPaths` to securely map the NFS storage to the
  sandboxed path `/var/lib/minetest`, ensuring all operations (including `preStart` and actual gameplay) persist
  directly to the NAS.

