# Vaultwarden Service Configuration

This document describes the deployment and configuration details of the **Vaultwarden** service in the `nixos-fleet`
infrastructure.

## Overview

Vaultwarden is an alternative Bitwarden server written in Rust, providing password vault features. It is deployed on the
general applications node, **`proxmox-applications-1`**. A replica still runs on
**`rpi4`** and Syncthing copies `/var/lib/vaultwarden`; the edge does not fail
over to the Pi.

## Networking and Ports

- **Internal Port**: `8222` (TCP, Rocket HTTP port)
- **Public Domain**: `https://vaultwarden.alexmayers.co.za` (reverse proxied via Caddy).
- **Admin Lock**: Caddy blocks requests to `/admin*` unless the request originates from the Tailscale IP range
  `100.64.0.0/10`.

## Secrets Management

- **`vaultwarden/env`**: Contains database connections and encryption key settings. Loaded directly by the service using
  `environmentFile`.

## Database Integration

Vaultwarden connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `vaultwarden`
- **Port**: `5432` (PgBouncer)

## Configurations

- **Signups**: New user signups are disabled (`SIGNUPS_ALLOWED = false`).
- **Features**: Experimental client features (like SSH key agent integration) are enabled:
  ```nix
  EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
  ```

## Stateful Synchronization & High Availability (Syncthing)

While Vaultwarden's core credentials database is replicated via PostgreSQL on `xcloud-postgres`, Vaultwarden also writes
attachment files and system metadata directly to its local filesystem directory (`/var/lib/vaultwarden`).

To keep the primary (`proxmox-applications-1`) and the Pi replica in sync, the
system configures a real-time **Syncthing** file synchronization daemon:

- **Scope**: Runs under system user `vaultwarden` to maintain file ownership.
- **Data Target**: Synchronizes `/var/lib/vaultwarden` state folder.
- **SSO Security & Network isolation**:
    - Global discovery, local discovery, and relays are disabled.
    - Syncthing binds directly to `tailscale0` IP interfaces.
    - Connections are routed strictly over Tailscale using hardcoded node addresses (
      `tcp://proxmox-applications-1:22000` and
      `tcp://rpi4:22000`).
- **Defaults**: Excludes default folders (`STNODEFAULTFOLDER = "true"`).
