# Grafana Service Configuration

This document describes the deployment and configuration details of the **Grafana** service in the `nixos-fleet`
infrastructure.

## Overview

Grafana provides system virtualization and dashboard analytics. In this fleet, it is deployed in a stateless clustered
architecture across
**`proxmox-observability-1`** and **`proxmox-observability-2`**. There is no `rpi4` instance: the Pi's replica was
never routable and has been removed.

## Networking and Ports

- **Internal Port**: `3000` (TCP, HTTP)
- **Public Domain**: `https://grafana.alexmayers.co.za` (reverse proxied via Caddy).
- **Load Balancing / Failover**: the internal Caddy on `proxmox-lb` balances `proxmox-observability-1:3000` and
  `proxmox-observability-2:3000` with `lb_policy cookie grafana_lb`, so a browser session sticks to one instance, with
  active health checks against `/api/health` every 5s. A node that fails its health check is taken out of rotation.

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
    - **Prometheus**: Default. Mimir query-frontend at `http://proxmox-lb:9009/prometheus` (long-term storage).
    - **Prometheus (local)**: The Prometheus agent on the same host (`http://127.0.0.1:9090`). Use this when Mimir or
      the LB is down; it only has what this agent scraped, not fleet-wide history.
    - **Loki**: `http://proxmox-lb:3100` (max lines `1000`).
    - **Alertmanager**: `http://proxmox-lb:9093`.
  Mimir/Loki/Alertmanager go through the LB so a Grafana on obs-1 still works if that node's local Mimir is down but
  the peer is up.
- **Dashboards**: Dashboards are loaded from `./grafana/dashboards` in the flake
  (`foldersFromFilesStructure`). Community JSON stays at that root. Fleet-authored
  boards live in `./grafana/dashboards/fleet/` and appear in Grafana as the
  `fleet` folder. The tree is copied to the Nix store at deploy.
    - Prefer a community dashboard (grafana.com or the exporter's upstream) over a custom one. Rewrite the datasource
      to the provisioned Prometheus (Mimir) and drop or fix panels whose `expr` does not match scraped series.
    - Community imports (already in-tree): Caddy, Caddy Hosts, Caddy standalone, Keycloak Quarkus, Node Exporter,
      PgBouncer, Postgres Exporter, Systemd Exporter, Tailscale API, Tailscale machine.
    - Fleet alert dashboards (`dashboards/fleet/fleet-*.json`) cover groups that
      have no working community mixin for these labels. Panel `expr` values are
      the same metrics as `services/mimir-rules.nix`.
    - Mapping: node/system/crash-loops → Node + Systemd; postgres/pgbouncer → those two; caddy → Caddy; keycloak →
      Keycloak Quarkus; tailscale-mesh → Tailscale; blackbox → `fleet-blackbox`; redis → `fleet-redis`; loki →
      `fleet-loki`; mimir/ruler → `fleet-mimir`; garage → `fleet-garage`; gitlab/runner → `fleet-gitlab`; ntfy →
      `fleet-ntfy`; truenas → `fleet-truenas`; smartctl → `fleet-smartctl`; GrafanaAlerts → `fleet-grafana`;
      prometheus → `fleet-prometheus`; backups/kernel → `fleet-backups-kernel`.
- **Console Log format**: Configured to output logs in `json` format for ingestion by Alloy/Loki.

## Key Configurations

- **Keycloak SSO integration**: Configured to use OIDC authentication:
    - **Issuer Realm**: `https://identity.alexmayers.co.za/realms/master`
    - **PKCE**: Enabled (`use_pkce = true`).
    - **RBAC**: Administrator rights (`GrafanaAdmin`) are dynamically assigned if the generic OIDC email matches
      `a.mayers102@gmail.com`. All other authenticated users are assigned the `Viewer` role.

`MemoryMax = 768M` ([memory.md](../memory.md)).

## Alerting

`GrafanaRequestsFailing` is in the `GrafanaAlerts` group
([`services/mimir-rules.nix`](../../services/mimir-rules.nix)). Dashboard:
`fleet-grafana`.
