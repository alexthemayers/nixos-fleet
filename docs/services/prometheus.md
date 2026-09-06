# Prometheus Monitoring Service Configuration

This document describes the deployment and configuration details of the **Prometheus** service in the `nixos-fleet`
infrastructure.

## Overview

Prometheus is the scrape-and-remote-write agent. It runs on
**`proxmox-observability-1`** and **`proxmox-observability-2`** in
`--enable-feature=agent` mode. There is no Prometheus on `rpi4`.

## Networking and Ports

- **Internal Port**: `9090` (TCP, HTTP)
- **Public Domain**: `https://prometheus.alexmayers.co.za` (reverse proxied via Caddy).
- **Firewall**: Exposes port `9090` to the Tailscale interface only.

## Remote Write Metrics Storage

To support long-term metrics history, Prometheus does not store metrics locally. Instead, it forwards all scraped
metrics to Mimir using remote write:

```nix
remoteWrite = [
  {
    url = "http://localhost:9009/api/v1/push";
  }
];
```

## Scrape Targets Configuration

Scrape tasks are defined inside `scrapeConfigs` with a default interval of `30s`:

- **`blackbox_http`**: Probes public endpoints through the Blackbox Exporter
  on `proxmox-observability-1:9115` (auth, gitlab, registry, coder, immich,
  jellyfin, vaultwarden, tasks, identity OIDC discovery, grafana, budget,
  proxmox, truenas, ntfy, paperless). Identity is
  `https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration`,
  not `/admin*` (CIDR-gated). Relabel:
  ```nix
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "proxmox-observability-1:9115"; }
  ];
  ```
  Alerts: [blackbox-exporter.md](blackbox-exporter.md).
- **`blackbox`**: scrapes the exporter process on obs-1 `:9115`.
- **`caddy`**: Scrapes HTTP proxy performance metrics from `xcloud-caddy:2019`
  and `proxmox-lb:2019`.
- **`prometheus`**: Scrapes `proxmox-observability-1:9090` and
  `proxmox-observability-2:9090`.
- **`postgres`**: Scrapes PostgreSQL cluster exporter on `xcloud-postgres:9187`.
- **`garage`**: Scrapes Garage admin `/metrics` on `proxmox-db-1:3903` and
  `proxmox-db-2:3903` (no metrics token). Cluster health, merkle, resync, and
  S3 5xx alerts live in the Mimir `garage` rule group
  ([garage.md](garage.md#alerting)).
- **`node`**: Collects system resources (CPU, memory, disk, network interface traffic, systemd state) from all target
  hosts utilizing node exporter agents running on port `9100`.
- **`truenas_scale`**: Scrapes TrueNAS system statistics by querying the Graphite Exporter bridge on
  `proxmox-observability-1:9108`. Mapped series use `job="truenas"`. Alerts:
  [truenas-graphite-exporter.md](truenas-graphite-exporter.md#alerting).
- **`loki`**: Scrapes both obs nodes on `:3100`. Cluster alerts:
  [loki.md](loki.md#alerting).
- **`tailscale-client-metrics`**: Scrapes `tailscale web --readonly` on `:9251`.
  DERP vs direct alerts: [tailscale.md](tailscale.md#alerting-derp-vs-direct).

## Cardinality drops

Some jobs carry `metric_relabel_configs` built by the `dropMetrics` helper,
which drops series by name at scrape time so they never reach Mimir:

- **`caddy`**: `caddy_rate_limit_process_time_seconds_*`, a histogram of the
  rate limiter's own bookkeeping per zone and handler.
- **`node exporter`**: `node_systemd_unit_state`, which duplicates the
  standalone systemd exporter per unit per state. The collector stays on for
  `node_systemd_units` and `node_systemd_socket_*`, which dashboards query.
- **`systemd exporter`**: the `systemd_unit_*_time_seconds` per-unit
  timestamps.

These exist because Mimir's per-tenant series cap is enforced per ingester and
rejecting a new series also stops the ruler writing its own results
([mimir.md](mimir.md#series-cap)). Prometheus anchors relabel regexes, so a
trailing `.*` is needed to catch histogram `_bucket`/`_sum`/`_count`
children.

Before adding a name, confirm no rule, alert, or dashboard `expr` reads it.
Grep the `expr` values specifically: a Grafana panel can carry an unused name
in its legacy `"metric"` field while querying something else, which is
exactly the case for `node_systemd_unit_state`. Rationale and the measured
per-series cost:
[mimir-series-headroom ADR](../adr/2026-09-05-mimir-series-headroom.md).

## Key Configurations

- **Log Format**: Overridden with `--log.format=json` to output structured logs.
- **Alertmanager Integration**: Integrates with local Alertmanager instances to fire warning/critical notifications.
- **User Permissions**: Deploys Alertmanager system services under static user/group `alertmanager` instead of dynamic
  users.
