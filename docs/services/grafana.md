# Grafana Service Configuration

This document describes the deployment and configuration details of the **Grafana** service in the `nixos-fleet`
infrastructure.

## Overview

Grafana provides dashboards and alerting UI. It runs on
**`proxmox-observability-debian`**. The Prometheus datasource is
`127.0.0.1:9090`. There is no `rpi4` instance.

## Networking and Ports

- **Internal Port**: `3000` (TCP, HTTP)
- **Public Domain**: `https://grafana.alexmayers.co.za` (reverse proxied via Caddy).
- **Upstream**: edge Caddy proxies `proxmox-observability-debian:3000` with a health
  check on `/api/health` every 5s. There is no second Grafana.

## Secrets Management

- **`grafana/admin_password`**: Password for the seed admin account.
- **`grafana/secret_key`**: Key used for signing internal session tokens.
- **`postgres/grafana_password`**: Password for external PostgreSQL access.
- **`grafana/oauth_secret`**: Client secret used to authenticate generic OAuth requests against Keycloak.

Grafana uses its built-in `$__file{}` file-lookup syntax (e.g. `$__file{/run/secrets/grafana/oauth_secret}`) to read
these secret values dynamically from sops-decrypted paths at runtime, preventing secrets from leaking into the Nix
store.

## Database Integration

Grafana is integrated with the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `grafana`
- **Port**: `5432` (PgBouncer)
- **Connection Limits**: Restricted to a maximum of `5` open and `5` idle connections to prevent connection starvation.

## Provisioning and Datasources

The Grafana instance is configured to auto-provision datasources and dashboards on startup:

- **Datasources**:
    - **Prometheus**: Default. Mimir query-frontend at
      `http://127.0.0.1:9009/prometheus` (same VM).
    - **Prometheus (local)**: The Prometheus agent on the same host (`http://127.0.0.1:9090`). Use this when Mimir is
      down; it only has what this agent scraped, not fleet-wide history.
    - **Loki**: `http://127.0.0.1:3100` (max lines `1000`).
    - **Alertmanager**: `http://127.0.0.1:9093`.
- **Dashboards**: Dashboards are loaded from `./grafana/dashboards` in the flake
  (`foldersFromFilesStructure`). Community JSON stays at that root. Fleet-authored
  boards live in `./grafana/dashboards/fleet/` and appear in Grafana as the
  `fleet` folder. The tree is copied to the Nix store at deploy.
    - Prefer a community dashboard (grafana.com or the exporter's upstream) over a custom one. Rewrite the datasource
      to the provisioned Prometheus (Mimir) and drop or fix panels whose `expr` does not match scraped series.
    - Community imports (already in-tree): Caddy, Caddy Hosts, Caddy standalone,
      Node Exporter, PgBouncer, Postgres Exporter, Systemd Exporter, Tailscale
      API, Tailscale machine. The Keycloak Quarkus MicroProfile import is gone:
      live series are Micrometer (`http_server_requests_seconds_*`, `jvm_*`,
      `vendor_*`), not `base_thread_count`.
    - Fleet alert dashboards (`dashboards/fleet/fleet-*.json`) cover groups that
      have no working community mixin for these labels. Panel `expr` values are
      the same metrics as `collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml`.
    - Mapping: node/system/crash-loops → Node + Systemd; postgres/pgbouncer →
      those two; caddy → Caddy; keycloak → `fleet-keycloak`; tailscale-mesh →
      Tailscale + `fleet-smokeping`; blackbox → `fleet-blackbox`; redis →
      `fleet-redis`; loki → `fleet-loki`; vector → `fleet-vector`; gitlab/runner →
      `fleet-gitlab`; ntfy → `fleet-ntfy`; alertmanager → `fleet-alertmanager`;
      truenas → `fleet-truenas` (`job="truenas_scale"`); smartctl → `fleet-smartctl`; GrafanaAlerts →
      `fleet-grafana`; prometheus → `fleet-prometheus`; backups/kernel →
      `fleet-backups-kernel`; updates/reboots → `fleet-updates`; hardware/sriov/gpu → `fleet-hardware`;
      media-automation → `fleet-media-automation`; immich → `fleet-immich`;
      iperf3 mesh → `fleet-iperf3`; NFS client congestion → `fleet-nfs`.
- **Console Log format**: Configured to output logs in `json` format for ingestion by Vector/Loki.

## Key Configurations

- **Edge gate then Grafana OIDC**: Caddy hybrid forward-auth sends the
  browser to `auth.alexmayers.co.za` (oauth2-proxy client). After that
  cookie is set, Grafana still does its own Keycloak login (client
  `grafana`). A 500 on Keycloak `/token` is a realm mapper/group bug
  (usually `parent_group` emptied instead of the space sentinel),
  not Grafana: [keycloak.md](keycloak.md).
- **Public MCP / API Bearer**: `edge.apiBearerBypass` skips oauth2-proxy
  for `Authorization: Bearer` on `/api/*` only. Create a Viewer service
  account in the Grafana UI; keep the token out of the repo and out of
  sops. The token is the public credential
  ([2026-11-05-grafana-api-bearer-bypass](../adr/2026-11-05-grafana-api-bearer-bypass.md)).
- **Keycloak SSO integration**: Configured to use OIDC authentication:
    - **Issuer Realm**: `https://identity.alexmayers.co.za/realms/master`
    - **PKCE**: Enabled (`use_pkce = true`).
    - **RBAC**: Grafana reads the OIDC `roles` claim. `role_attribute_strict`
      is on, so login fails without a matching role.

| Keycloak | Grafana |
| --- | --- |
| `grafana:read` (default realm role) | `Viewer` |
| group `grafana admin` | `GrafanaAdmin` |

Every Keycloak user has `grafana:read`. Put a user in `grafana admin` only
if they need server admin. Do not use realm role `admin`. See
[2026-09-07-grafana-sso-groups](../adr/2026-09-07-grafana-sso-groups.md).

`MemoryMax = 1G` and `MemoryHigh = 1G` ([memory.md](../memory.md)).
A 512M high watermark sat under the Grafana 13 working set and stalled
the process.

## Alerting

`GrafanaRequestsFailing` is in the `GrafanaAlerts` group
([`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml)). Dashboard:
`fleet-grafana`.
