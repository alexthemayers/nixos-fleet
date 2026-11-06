# Ntfy Notification Service Configuration

This document describes the deployment and configuration details of the
**ntfy** (notification delivery) and **alertmanager-ntfy** (Alertmanager
webhook forwarder) services in the `nixos-fleet` infrastructure.

## Overview

The ntfy system delivers notifications to mobile apps and browsers.
**ntfy-sh** runs on **`proxmox-observability-debian`**. There is one SQLite
database. Edge Caddy reverse-proxies
`https://ntfy.alexmayers.co.za` to that instance
([no internal LB](../adr/2026-09-07-no-internal-lb.md)).

## Networking and Ports

- **ntfy-sh**: Listens on port `2586` (TCP, HTTP), reverse proxied via Caddy (`https://ntfy.alexmayers.co.za`).
- **alertmanager-ntfy**: group webhook on port `8095` (TCP, HTTP) on localhost.
  Alertmanager POSTs to ntfy on this same host
  (`http://proxmox-observability.bee-phrygian.ts.net:2586`).

## Secrets Management

- **`ntfy/alertmanager_password`**: Password assigned to the `alertmanager` system account in the ntfy user database.
- **`ntfy/password`**: Password assigned to the administrator account `alex` in the ntfy user database.

Secrets are rendered into `alertmanager-ntfy.env` for the group webhook.

## Custom User Provisioning (`ntfy-custom-setup`)

By default, `ntfy-sh` does not support declarative user management in NixOS. To resolve this:

1. **Static user**: nixpkgs runs ntfy as `DynamicUser`. This module forces
   `DynamicUser = false`, declares `users.users.ntfy-sh`, and sets the unit
   `User`/`Group` so the daemon, `ntfy-custom-setup`, and sops files share
   `/var/lib/ntfy-sh`.
2. **Bootstrap Script**: A oneshot systemd service (`ntfy-custom-setup`) runs after the daemon starts:
    - It waits for the SQLite database `/var/lib/ntfy-sh/user.db` to be initialized.
    - Creates/updates the admin user `alex`.
    - Creates the `alertmanager` user and restricts it to **write-only** access on the `alerts` topic:
      ```bash
      ntfy access -H /var/lib/ntfy-sh/user.db alertmanager alerts write-only
      ```

## Webhook Forwarder (`alertmanager-ntfy.service`)

Alertmanager posts **one webhook per group**. The Python listener
([alertmanager-ntfy.py](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/alertmanager-ntfy.py)) sends
**one ntfy message** for that payload (title from `groupLabels` plus firing
count, body from every member). The previous `alertmanager-ntfy` binary
templated the per-alert struct and emitted one phone push per series, which made
kube-prometheus summaries look like identical bursts.

- **Auth**: ntfy-sh on **`proxmox-observability`** `:2586` as user `alertmanager` (JSON body; `priority` is an integer 1–5).
- **Topic**: `alerts`.
- **Filesystem grouping**: Alertmanager `group_by` for disk alerts is
  `alertname + instance + device`.

## Alerting

Rules live in the `ntfy` group in
[`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml).
Dashboard: `fleet-ntfy`.

| Alert | Catches |
|---|---|
| `NtfyPublishFailures` | `ntfy_messages_published_failure` increased |
| `NtfyHttp5xxRate` | HTTP 5xx above 5% of `ntfy_http_requests_total` |

`TargetDown` covers a dead scrape. If ntfy on `proxmox-observability` is down, pages stop.

See [2026-09-04-ntfy-json-priority-single-writer.md](../adr/2026-09-04-ntfy-json-priority-single-writer.md).
JSON `priority` is still an integer. There is no Alertmanager gossip cluster:

```bash
ssh root@proxmox-observability amtool --alertmanager.url=http://127.0.0.1:9093 -o extended cluster show
```
