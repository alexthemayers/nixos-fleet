# Ntfy Notification Service Configuration

This document describes the deployment and configuration details of the **ntfy** (notification delivery) and *
*alertmanager-ntfy** (Alertmanager webhook forwarder) services in the `nixos-fleet` infrastructure.

## Overview

The ntfy system delivers notifications to mobile apps and browsers. In this fleet, it is deployed on the observability
node, **`proxmox-observability`**, with a failover instance deployed on **`rpi4`**.

## Networking and Ports

- **ntfy-sh**: Listens on port `2586` (TCP, HTTP), reverse proxied via Caddy (`https://ntfy.alexmayers.co.za`).
- **alertmanager-ntfy**: Listens on port `8095` (TCP, HTTP) on localhost.

## Secrets Management

- **`ntfy/alertmanager_password`**: Password assigned to the `alertmanager` system account in the ntfy user database.
- **`ntfy/password`**: Password assigned to the administrator account `alex` in the ntfy user database.

Secrets are rendered into `alertmanager-ntfy.yml` templates and utilized by oneshot setup scripts.

## Custom User Provisioning (`ntfy-custom-setup`)

By default, `ntfy-sh` does not support declarative user management in NixOS. To resolve this:

1. **DynamicUser Disabled**: `systemd.services.ntfy-sh.serviceConfig.DynamicUser` is set to `false` so the daemon runs
   as a static user `ntfy-sh` and maintains file ownership.
2. **Bootstrap Script**: A oneshot systemd service (`ntfy-custom-setup`) runs after the daemon starts:
    - It waits for the SQLite database `/var/lib/ntfy-sh/user.db` to be initialized.
    - Creates/updates the admin user `alex`.
    - Creates the `alertmanager` user and restricts it to **write-only** access on the `alerts` topic:
      ```bash
      ntfy access -H /var/lib/ntfy-sh/user.db alertmanager alerts write-only
      ```

## Webhook Forwarder (`alertmanager-ntfy`)

The `alertmanager-ntfy` daemon translates alerts sent by Alertmanager into push notifications. It is configured via sops
template `alertmanager-ntfy.yml`:

- **Auth**: Auths with ntfy-sh on `127.0.0.1:2586` using user `alertmanager`.
- **Topic**: Pushes to topic `alerts`.
- **Priorities & Emojis Mappings**: Converts alert severity labels dynamically:
    - Resolved alert &rarr; default priority, `white_check_mark` tag, "Resolved:" prefix.
    - Critical alert &rarr; urgent priority, `rotating_light` tag.
    - Warning alert &rarr; high priority, `warning` tag.
    - Info alert &rarr; low priority, `information_source` tag.
- **Details**: Injects descriptions and attaches generator URLs as click-actions.
