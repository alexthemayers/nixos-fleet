# Prometheus Monitoring Service Configuration

This document describes the deployment and configuration details of the **Prometheus** service in the `nixos-fleet`
infrastructure.

## Overview

Prometheus is a local server with 62 days of TSDB. It runs on
**`proxmox-observability-debian`**. There is no Prometheus on `rpi4`
and no remote-write to Mimir
([local metrics and logs](../adr/2026-11-04-local-metrics-and-logs.md)).

## Networking and Ports

- **Internal Port**: `9090` (TCP, HTTP)
- **Reachability**: tailnet only (`proxmox-observability-debian:9090`). There
  is no `prometheus.alexmayers.co.za` vhost ([caddy.md](caddy.md)).
- **Firewall**: Exposes port `9090` to the Tailscale interface only.

## Config source

Scrape jobs, Alertmanager, Graphite mapping, and alert rules are committed
files under
[`roles/observability/files/`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/).
Apply with `make deploy-debian-observability`.

## Scrape Targets Configuration

Scrape tasks live in `prometheus.yml` with a default interval of `30s`:

- **`blackbox_http`**: Probes public endpoints through the Blackbox Exporter
  on `proxmox-observability-debian:9115`. Targets are listed in the
  committed scrape file (keep them aligned with `fleet.apps`
  `probe.public`). Identity is OIDC discovery, not `/admin*`
  (CIDR-gated). Relabel:
  ```nix
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "proxmox-observability:9115"; }
  ];
  ```
  Alerts: [blackbox-exporter.md](blackbox-exporter.md).
- **`blackbox_http_internal`**: same prober, `fleet.internalHttpProbeTargets`
  (*arr stack and FlareSolverr on apps-1).
- **`blackbox`**: scrapes the exporter process on `proxmox-observability:9115`.
- **`caddy`**: Scrapes HTTP proxy performance metrics from `xcloud-caddy:2019`.
- **`prometheus`**: Scrapes `proxmox-observability:9090`.
- **`alertmanager`**: Scrapes `proxmox-observability:9093`. Alerts:
  `AlertmanagerConfigReloadFailed`, `AlertmanagerNotificationsFailing`.
  Dashboard: `fleet-alertmanager`.
- **`postgres`**: Scrapes PostgreSQL exporter on `xcloud-postgres:9187`.
- **`postgres_pgbouncer`**: Scrapes PgBouncer exporter on `xcloud-postgres`.
- **`systemd exporter`**: Fleet systemd units (crash-loop series live here). Includes the Debian guests `proxmox-applications-debian` and `proxmox-gitlab-debian` (binary from `fleet.debian_guest.monitoring`, bound to the tailnet address).
- **`node exporter`**: CPU, memory, disk, network, systemd counts on `:9100`
  for every inventory host. `collector.mountstats` is on: per-export NFS
  WRITE/COMMIT/LOOKUP latency and vfs events. Alerts: Mimir `nfs` group
  ([how-to-configure-nfs-mounts.md](../how-to-configure-nfs-mounts.md)).
  Dashboard: `fleet-nfs`. Garage iSCSI login/mount alerts use
  `systemd_unit_state` and `node_filesystem_*`
  ([garage-iscsi.md](../runbooks/garage-iscsi.md)).
- **`tailscale exporter`** / **`tailscale-client-metrics`**: DERP vs direct
  ([tailscale.md](tailscale.md#alerting-derp-vs-direct)).
- **`smokeping-probers`**: ICMP latency from the smokeping exporter.
  Dashboard: `fleet-smokeping`.
- **`keycloak`**, **`grafana`**, **`gitlab`**, **`gitlab-runner`**, **`coder`**,
  **`vikunja`**, **`ntfy`**, **`oauth2-proxy`**, **`vector`**, **`mimir`**,
  **`redis`**: native `/metrics` or the matching exporter on the service host.
  Redis is three exporters on `xcloud-postgres:9121`/`9122`/`9123`
  (`oauth2-proxy`, `vikunja`, `paperless`), labelled `redis_instance`.
  Hostname:port jobs get a `host` relabel from the address. Blackbox URL
  probes do not (instance is the URL). Eval fails if a hostname:port job
  omits that relabel.
- **`garage`**: Garage admin `/metrics` on `proxmox-observability:3903`
  (no metrics token). Cluster health, merkle, resync, and
  S3 5xx alerts live in the Mimir `garage` rule group
  ([garage.md](garage.md#alerting)).
- **`loki`**: Scrapes `proxmox-observability:3100`. Cluster alerts:
  [loki.md](loki.md#alerting).
- **`smartctl`**: `proxmox:9633` (ansible `smartctl_exporter` on the
  hypervisor).
- **`truenas_scale`**: Graphite exporter bridge on
  `proxmox-observability:9108`. Mapped series use `job="truenas"`. Defined
  via the graphite mapping in
  [`roles/observability/files/graphite-mapping.yml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/graphite-mapping.yml).
  Alerts:
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

- **Log Format**: `--log.format=json`.
- **Retention**: `--storage.tsdb.retention.time=62d`.
- **Rules**: Prometheus evaluates
  [`rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml)
  and sends to Alertmanager on this guest (`:9093`).

## Alerting

`prometheus_*` rules (config reload, TSDB) are in the `prometheus` group.
SMART is `smartctl` (hypervisor `:9633`), including
`SmartctlNvmeWearHigh` / `Critical` on `smartctl_device_percentage_used`.
Backups and kernel OOM are `backups` / `kernel-stability`. Dashboards:
`fleet-prometheus`, `fleet-smartctl`, `fleet-backups-kernel`.

Updates are the `updates` group: `HostSecurityUpdatesPending` (3 d),
`HostRebootRequired` (36 h), `HostUpdatesStale` (45 d), `HypervisorUpdatesStale`
(100 d), and `HostAptCacheStale`, all from `apt_upgrades_pending`,
`node_reboot_required`, and `apt_package_cache_timestamp_seconds` (the
node-exporter-collectors apt timer; the series is absent when nothing is
pending). Dashboard: `fleet-updates`. Process:
[updates.md](../runbooks/updates.md).
