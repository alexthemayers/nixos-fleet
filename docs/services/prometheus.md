# Prometheus Monitoring Service Configuration

This document describes the deployment and configuration details of the **Prometheus** service in the `nixos-fleet`
infrastructure.

## Overview

Prometheus is the scrape-and-remote-write agent. It runs on
**`proxmox-observability`** in `--enable-feature=agent` mode. There is no
Prometheus on `rpi4`.

## Networking and Ports

- **Internal Port**: `9090` (TCP, HTTP)
- **Reachability**: tailnet only (`proxmox-observability:9090`). There is no
  `prometheus.alexmayers.co.za` vhost ([caddy.md](caddy.md)).
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
  on `proxmox-observability:9115` (auth, gitlab, registry, coder, immich,
  jellyfin, vaultwarden, tasks, identity OIDC discovery, grafana, budget,
  proxmox, truenas, ntfy, paperless). Identity is
  `https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration`,
  not `/admin*` (CIDR-gated). Relabel:
  ```nix
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "proxmox-observability:9115"; }
  ];
  ```
  Alerts: [blackbox-exporter.md](blackbox-exporter.md).
- **`blackbox_http_internal`**: same prober, tailnet HTTP UIs
  (Radarr `:7878`, Sonarr `:8989`, Prowlarr `:9696`, qBittorrent
  `:8081`, FlareSolverr `:8191` on apps-1).
- **`blackbox`**: scrapes the exporter process on obs-1 `:9115`.
- **`caddy`**: Scrapes HTTP proxy performance metrics from `xcloud-caddy:2019`.
- **`prometheus`**: Scrapes `proxmox-observability:9090`.
- **`postgres`**: Scrapes PostgreSQL exporter on `xcloud-postgres:9187`.
- **`postgres_pgbouncer`**: Scrapes PgBouncer exporter on `xcloud-postgres`.
- **`systemd exporter`**: Fleet systemd units (crash-loop series live here).
- **`node exporter`**: CPU, memory, disk, network, systemd counts on `:9100`
  for every inventory host.
- **`tailscale exporter`** / **`tailscale-client-metrics`**: DERP vs direct
  ([tailscale.md](tailscale.md#alerting-derp-vs-direct)).
- **`smokeping-probers`**: ICMP latency from the smokeping exporter.
- **`keycloak`**, **`grafana`**, **`gitlab`**, **`gitlab-runner`**, **`coder`**,
  **`vikunja`**, **`ntfy`**, **`oauth2-proxy`**, **`vector`**, **`mimir`**,
  **`redis`**: native `/metrics` or the matching exporter on the service host.
- **`garage`**: Garage admin `/metrics` on `proxmox-observability:3903`
  (no metrics token). Cluster health, merkle, resync, and
  S3 5xx alerts live in the Mimir `garage` rule group
  ([garage.md](garage.md#alerting)).
- **`loki`**: Scrapes obs-1 on `:3100`. Cluster alerts:
  [loki.md](loki.md#alerting).
- **`smartctl`**: `proxmox:9633` (ansible `smartctl_exporter` on the
  hypervisor).
- **`truenas_scale`**: Graphite exporter bridge on
  `proxmox-observability:9108`. Mapped series use `job="truenas"`. Defined
  in `services/truenas/graphite_exporter.nix`. Alerts:
  [truenas-graphite-exporter.md](truenas-graphite-exporter.md#alerting).

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
- **Rules**: Prometheus runs as an agent. Mimir evaluates
  `services/mimir-rules.nix` and sends to Alertmanager on obs-1
  (`:9093`). This file also defines the Alertmanager unit
  (static user `alertmanager`, not DynamicUser).

## Alerting

Agent-mode `prometheus_*` rules that still export data (config reload, TSDB,
remote-write) are in the `prometheus` group. SMART is `smartctl` (hypervisor
`:9633`), including `SmartctlNvmeWearHigh` / `Critical` on
`smartctl_device_percentage_used` (live 21% on `nvme0`). Backups and kernel
OOM are `backups` / `kernel-stability`. Dashboards: `fleet-prometheus`,
`fleet-smartctl`, `fleet-backups-kernel`.
