# Caddy Reverse Proxy Service Configuration

This document describes the deployment and configuration details of the **Caddy Reverse Proxy** service in the
`nixos-fleet` infrastructure.

## Overview

Caddy serves as the central HTTP/HTTPS entry point and reverse proxy for the entire fleet. It is deployed on the cloud
gateway node, **`xcloud-caddy`**.

## Networking and Ports

- **HTTP Ports**: `80` (TCP, redirected to HTTPS) and `443` (TCP/UDP, with QUIC/HTTP3 support).
- **Admin & Metrics Interface**: Listen on `0.0.0.0:2019` over the `tailscale0` interface only.
- **Luanti Game Traffic**: Port `30000` (UDP) is opened and managed via the `caddy-l4` Layer 4 proxy plugin.

## Secrets Management

- **`oauth2-proxy/blackbox_token`**: Used to compile the `caddy-env` environment file. This token allows Prometheus
  Blackbox Exporter probes to bypass forward authentication.

## Reverse Proxy Virtual Hosts

Caddy forwards external subdomains to internal Tailscale services:

- `auth.alexmayers.co.za` &rarr; `127.0.0.1:4180` (oauth2-proxy)
- `jellyfin.alexmayers.co.za` &rarr; `proxmox-applications-1:8096`
- `immich.alexmayers.co.za` &rarr; `proxmox-applications-1:2283`
- `grafana.alexmayers.co.za` &rarr; `proxmox-observability-1:3000` / `proxmox-observability-2:3000` / failover
  `rpi4:3000`
- `prometheus.alexmayers.co.za` &rarr; `proxmox-observability-1:9090` / `proxmox-observability-2:9090` / failover
  `rpi4:9090`
- `alertmanager.alexmayers.co.za` &rarr; `proxmox-observability-1:9093` / `proxmox-observability-2:9093` / failover
  `rpi4:9093`
- `gitlab.alexmayers.co.za` &rarr; `proxmox-applications-2:8080`
- `registry.alexmayers.co.za` &rarr; `proxmox-applications-2:5005`
- `coder.alexmayers.co.za` &rarr; `proxmox-dev:7080`
- `budget.alexmayers.co.za` &rarr; `proxmox-applications-1:5006`
- `paperless.alexmayers.co.za` &rarr; `proxmox-applications-1:28981` / `proxmox-applications-2:28981`
- `identity.alexmayers.co.za` &rarr; `proxmox-applications-1:7777` / `proxmox-applications-2:7777` / failover
  `rpi4:7777` (Keycloak)
- `vaultwarden.alexmayers.co.za` &rarr; `proxmox-applications-1:8222` / failover `rpi4:8222`
- `s3.alexmayers.co.za` &rarr; `proxmox-db-1:3902` / `proxmox-db-2:3902` / failover `rpi4:3902` (Garage)
- `tasks.alexmayers.co.za` &rarr; `proxmox-applications-1:3456` / `proxmox-applications-2:3456` (Vikunja)
- `proxmox.alexmayers.co.za` &rarr; `https://proxmox:8006` (insecure TLS bypass)
- `truenas.alexmayers.co.za` &rarr; `http://truenas-scale:80`
- `ntfy.alexmayers.co.za` &rarr; `proxmox-observability-1:2586` / `proxmox-observability-2:2586` / failover `rpi4:2586`

## Key Configurations

- **Security Headers**: Enforces strict transport security (HSTS), frame options, and mime-type protection:
  ```caddy
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    Referrer-Policy "strict-origin-when-cross-origin"
  }
  ```
- **Forward Authentication Integration**: Routes subdomains (Grafana, Prometheus, Budget, Paperless, Proxmox, TrueNAS)
  through `oauth2-proxy` locally before reverse proxying:
  ```caddy
  forward_auth @requireAuth 127.0.0.1:4180 {
    uri /oauth2/auth
    copy_headers X-Auth-Request-User X-Auth-Request-Email
  }
  ```
- **Layer 4 Proxy (`caddy-l4`)**: Custom built package containing the `caddy-l4` plugin to proxy UDP gaming packets
  directly to the host running Luanti/Minetest:
  ```caddy
  layer4 {
    udp/:30000 {
      route {
        proxy udp/proxmox-applications-1:30000
      }
    }
  }
  ```
- **Vaultwarden Admin Restriction**: Blocks requests to `/admin*` unless the request originates from the Tailscale IP
  range `100.64.0.0/10`.
