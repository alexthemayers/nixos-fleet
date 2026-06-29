# Grafana Service Configuration

This document describes the deployment and configuration details of the **Grafana** service in the `nixos-fleet`
infrastructure.

## Overview

Grafana provides system virtualization and dashboard analytics. In this fleet, it is deployed on *
*`proxmox-observability`** as the primary metrics visualizer, with a failover instance configured on the backup node *
*`rpi4`**.

## Networking and Ports

- **Internal Port**: `3000` (TCP, HTTP)
- **Public Domain**: `https://grafana.alexmayers.co.za` (reverse proxied via Caddy).
- **Load Balancing / Failover**: Caddy uses `lb_policy first` to forward requests to `proxmox-observability:3000` and
  automatically fails over to `rpi4:3000` if the primary node goes offline.

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
    - **Prometheus**: Default datasource, points to Mimir query-frontend at `http://localhost:9009/prometheus`.
    - **Loki**: System log source, points to Loki API at `http://localhost:3100` (max lines set to `1000`).
    - **Alertmanager**: Prometheus alert manager dashboard source, points to `http://localhost:9093`.
- **Dashboards**: Dashboards are loaded dynamically from the local directory `./grafana/dashboards` in the flake output.
  This directory is copied directly to the Nix store at deployment, ensuring dashboards are tracked in git and loaded
  automatically.
    - Dashboards include: Caddy, Caddy Hosts, Keycloak Quarkus, Node Exporter, PgBouncer, Postgres Exporter, Systemd
      Exporter, and Tailscale API.
- **Console Log format**: Configured to output logs in `json` format for ingestion by Alloy/Loki.

## Key Configurations

- **Keycloak SSO integration**: Configured to use OIDC authentication:
    - **Issuer Realm**: `https://identity.alexmayers.co.za/realms/master`
    - **PKCE**: Enabled (`use_pkce = true`).
    - **RBAC**: Administrator rights (`GrafanaAdmin`) are dynamically assigned if the generic OIDC email matches
      `a.mayers102@gmail.com`. All other authenticated users are assigned the `Viewer` role.
