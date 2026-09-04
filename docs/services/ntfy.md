# Ntfy Notification Service Configuration

This document describes the deployment and configuration details of the **ntfy** (notification delivery) and *
*alertmanager-ntfy** (Alertmanager webhook forwarder) services in the `nixos-fleet` infrastructure.

## Overview

The ntfy system delivers notifications to mobile apps and browsers. **ntfy-sh**
runs on **`proxmox-observability-1`** and **`proxmox-observability-2`**. The two
SQLite databases are **not** replicated. Internal Caddy uses `lb_policy first`,
so clients stick to obs-1 while it is healthy.

There is no `rpi4` ntfy instance.

## Networking and Ports

- **ntfy-sh**: Listens on port `2586` (TCP, HTTP), reverse proxied via Caddy (`https://ntfy.alexmayers.co.za`).
- **alertmanager-ntfy**: group webhook on port `8095` (TCP, HTTP) on localhost.
  Both obs nodes POST to **obs-1** ntfy (`http://proxmox-observability-1.bee-phrygian.ts.net:2586`)
  so a notification elected on obs-2 still reaches phones subscribed via Caddy `first`.

## Secrets Management

- **`ntfy/alertmanager_password`**: Password assigned to the `alertmanager` system account in the ntfy user database.
- **`ntfy/password`**: Password assigned to the administrator account `alex` in the ntfy user database.

Secrets are rendered into `alertmanager-ntfy.env` for the group webhook.

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

## Webhook Forwarder (`alertmanager-ntfy.service`)

Alertmanager posts **one webhook per group**. The Python listener
([services/ntfy-group-webhook.py](../../services/ntfy-group-webhook.py)) sends
**one ntfy message** for that payload (title from `groupLabels` plus firing
count, body from every member). The previous `alertmanager-ntfy` binary
templated the per-alert struct and emitted one phone push per series, which made
kube-prometheus summaries look like identical bursts.

- **Auth**: ntfy-sh on **obs-1** `:2586` as user `alertmanager` (JSON body; `priority` is an integer 1–5).
- **Topic**: `alerts`.
- **Filesystem grouping**: Alertmanager `group_by` for disk alerts is
  `alertname + instance + device`. `LowDiskSpace` is inhibited while
  `NodeFilesystemAlmostOutOfSpace` is firing on the same instance and device.

See [2026-09-04-ntfy-json-priority-single-writer.md](../adr/2026-09-04-ntfy-json-priority-single-writer.md).

Both obs nodes run Alertmanager. A gossip split doubles notifications. Check:

```bash
ssh root@proxmox-observability-1 amtool --alertmanager.url=http://127.0.0.1:9093 -o extended cluster show
ssh root@proxmox-observability-2 amtool --alertmanager.url=http://127.0.0.1:9093 -o extended cluster show
```
