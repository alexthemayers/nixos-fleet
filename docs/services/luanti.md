# Luanti Game Server Service Configuration

This document describes the deployment and configuration details of the **Luanti** (formerly Minetest) game server
service in the `nixos-fleet` infrastructure.

## Overview

Luanti is an open-source voxel game engine. In this fleet, the game server is deployed on the gaming and compilation
node, **`proxmox-gaming`**.

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
