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

Routing is **two-tier**. This edge Caddy on `xcloud-caddy` terminates TLS and applies authentication, then forwards
almost everything to the internal load balancer as a single upstream, `proxmox-lb:80`, preserving the `Host` header.
The internal Caddy (`services/caddy-internal.nix`, documented in [caddy-internal.md](caddy-internal.md)) owns the
per-service backend lists, health checks and failover. Backend hostnames therefore do **not** appear here.

Edge vhosts:

- `auth.alexmayers.co.za` &rarr; `127.0.0.1:4180` (oauth2-proxy, local to this host)
- `proxmox.alexmayers.co.za` &rarr; `https://proxmox:8006` (direct; insecure TLS bypass for the hypervisor's self-signed
  certificate)
- `truenas.alexmayers.co.za` &rarr; `http://truenas-scale:80` (direct)
- `vaultwarden.alexmayers.co.za` &rarr; `proxmox-lb:80` (same as the other app
  vhosts; the Pi is not an edge upstream)
- `jellyfin`, `immich`, `grafana`, `gitlab`, `registry`, `coder`, `budget`, `paperless`, `identity`, `tasks`, `ntfy`
  &rarr; `proxmox-lb:80`

There are **no** `prometheus.alexmayers.co.za`, `alertmanager.alexmayers.co.za`, `s3.alexmayers.co.za` or
`attic.alexmayers.co.za` vhosts. Attic is tailnet-only; NAR fetch and
`nix copy --from` use `http://proxmox-dev:8080/attic` (not the LB). The other unlisted
services are reachable only over the tailnet, via the internal load balancer on dedicated ports (`proxmox-lb:9009` for
Mimir, `proxmox-lb:9093` for Alertmanager, `proxmox-lb:3902` for Garage S3, `proxmox-lb:3100` for Loki).

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
- **Rate Limiting (`caddy-ratelimit`)**: Applied per `{remote_host}` in three tiers, all over a 1 minute window.
  Tailscale (`100.64.0.0/10`) and loopback sources are exempt where the zone declares a `match`:
    - **Standard** — 500 events/min
    - **Heavy** — 1000 events/min
    - **Ultra heavy** — 2000 events/min
    - **Vaultwarden** gets its own pair of zones: 100/min against `/identity/connect/token` specifically, to slow
      credential stuffing against the vault, and 1000/min for everything else.
- **Layer 4 Proxy (`caddy-l4`)**: Custom built package containing the `caddy-l4` plugin to proxy UDP game traffic.
  Note these forward to the **internal load balancer**, which relays to the application host:
  ```caddy
  layer4 {
    udp/:30000 {
      route {
        proxy udp/proxmox-lb:30000
      }
    }
  }
  ```
- **Admin Restrictions**: Requests to `/admin*` are blocked unless they originate from the Tailscale range
  `100.64.0.0/10`. This applies to **both** `vaultwarden.alexmayers.co.za` and `identity.alexmayers.co.za` — the
  Keycloak admin console was previously reachable from the public internet behind nothing but its own login form.
- **Admin API**: Caddy's own admin endpoint is bound to `127.0.0.1:2019` and is not opened on any interface.

## Alerting

Rules live in the `caddy` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). Caddy does not
export `caddy_tls_*`; 5xx is on
`caddy_http_request_duration_seconds_count{code=...}`.

| Alert | Catches |
|---|---|
| `CaddyHigh5xxErrorRate` | 5xx above 5% of requests |
| `CaddyUpstreamUnhealthy` | `caddy_reverse_proxy_upstreams_healthy == 0` |
| `CaddyRequestErrors` | `caddy_http_request_errors_total` rising |
