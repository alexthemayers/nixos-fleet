# Prometheus Monitoring Service Configuration

This document describes the deployment and configuration details of the **Prometheus** service in the `nixos-fleet` infrastructure.

## Overview
Prometheus is the core system monitor, scraping metrics from nodes and services across the fleet. It is deployed on the observability node, **`proxmox-observability`**, with a failover instance deployed on **`rpi4`**.

## Networking and Ports
- **Internal Port**: `9090` (TCP, HTTP)
- **Public Domain**: `https://prometheus.alexmayers.co.za` (reverse proxied via Caddy).
- **Firewall**: Exposes port `9090` to the Tailscale interface only.

## Remote Write Metrics Storage
To support long-term metrics history, Prometheus does not store metrics locally. Instead, it forwards all scraped metrics to Mimir using remote write:
```nix
remoteWrite = [
  {
    url = "http://localhost:9009/api/v1/push";
  }
];
```

## Scrape Targets Configuration
Scrape tasks are defined inside `scrapeConfigs` with a default interval of `30s`:
- **`blackbox_http`**: Queries the Blackbox Exporter running on `rpi4:9115` to probe public endpoints (auth, gitlab, registry, coder, immich, jellyfin, vaultwarden, tasks, identity, grafana, budget, proxmox, truenas, s3, ntfy, paperless). It rewrites targets dynamically to route through the prober:
  ```nix
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "rpi4:9115"; }
  ];
  ```
- **`caddy`**: Scrapes HTTP proxy performance metrics from `xcloud-caddy:2019`.
- **`prometheus`**: Scrapes local performance statistics from `proxmox-observability:9090` and `rpi4:9090`.
- **`postgres`**: Scrapes PostgreSQL cluster exporter on `xcloud-postgres:9187`.
- **`node`**: Collects system resources (CPU, memory, disk, network interface traffic, systemd state) from all target hosts utilizing node exporter agents running on port `9100`.
- **`truenas_scale`**: Scrapes TrueNAS system statistics by querying the Graphite Exporter bridge on `proxmox-observability:9108`.

## Key Configurations
- **Log Format**: Overridden with `--log.format=json` to output structured logs.
- **Alertmanager Integration**: Integrates with local Alertmanager instances to fire warning/critical notifications.
- **User Permissions**: Deploys Alertmanager system services under static user/group `alertmanager` instead of dynamic users.
