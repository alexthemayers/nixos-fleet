# Vaultwarden Service Configuration

This document describes the deployment and configuration details of the **Vaultwarden** service in the `nixos-fleet`
infrastructure.

## Overview

Vaultwarden is an alternative Bitwarden server written in Rust, providing password vault features. It runs on
**`proxmox-applications-debian`**. Attachments stay in `/var/lib/vaultwarden` on that guest.

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

## Local state

Credentials are in PostgreSQL on `xcloud-postgres`. Attachment files and
metadata live in `/var/lib/vaultwarden` on the Debian guest. There is no
Syncthing copy. The edge still proxies only this host
([adr/2026-09-06-vaultwarden-no-edge-failover.md](../adr/2026-09-06-vaultwarden-no-edge-failover.md)).
