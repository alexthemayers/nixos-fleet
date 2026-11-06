# Caddy Reverse Proxy Service Configuration

This document describes the deployment and configuration details of the **Caddy Reverse Proxy** service in the
`nixos-fleet` infrastructure.

## Overview

Caddy serves as the central HTTP/HTTPS entry point and reverse proxy for the entire fleet. It is deployed on the cloud
gateway node, **`xcloud-caddy`**.

## Networking and Ports

- **HTTP Ports**: `80` (TCP, redirected to HTTPS) and `443` (TCP/UDP, with QUIC/HTTP3 support).
- **Admin & Metrics Interface**: Metrics listen on `0.0.0.0:2019` over
  `tailscale0` only. Caddy's own admin API is `127.0.0.1:2020`.
- **Game Traffic**: UDP `27960` (OpenArena) and `30000` (Luanti) come from
  `fleet.apps.*.udp` and are proxied via `caddy-l4` to
  `proxmox-applications-debian`.

## Secrets Management

- **`oauth2-proxy/blackbox_token`**: Used to compile the `caddy-env` environment file. This token allows Prometheus
  Blackbox Exporter probes to bypass forward authentication.

## Reverse Proxy Virtual Hosts

Routing is **one-tier**. This edge Caddy on `xcloud-caddy` terminates TLS and
applies authentication, then reverse-proxies each vhost to the process port
on the serving VM
([no internal LB](../adr/2026-09-07-no-internal-lb.md)).
HTTP vhosts and UDP listeners are generated from
[`fleet/apps/`](../../fleet/apps/). The `:2019` metrics site is local to
this module.

Edge vhosts (facts in the registry files, not here):

- `auth.alexmayers.co.za` &rarr; loopback `:4180` (oauth2-proxy)
- `proxmox.alexmayers.co.za` &rarr; `https://proxmox:8006` (insecure TLS)
- `truenas.alexmayers.co.za` &rarr; `truenas-scale:80`
- `jellyfin`, `immich`, `budget`, `paperless`, `identity`, `tasks`
  &rarr; `proxmox-applications-debian`
- `vaultwarden` &rarr; `proxmox-applications-debian`
  Identity health-checks `/health/ready` on `:9000` only. Do not mark
  that upstream unhealthy on HTTP 5xx from `/token`: one mapper
  exception then 503s every SSO callback.
  Immich retries the dial for 45s (`lb_try_duration`) with no
  `health_uri`: a health check that marked the only upstream down
  would 502 every request while `immich-server` restarts.
- `gitlab`, `registry` &rarr; `proxmox-gitlab-debian` (`:8080` and `:5005`)
- `grafana`, `ntfy` &rarr; `proxmox-observability`

There are **no** `prometheus.alexmayers.co.za` or
`alertmanager.alexmayers.co.za` vhosts. The other unlisted
services are reachable only over the tailnet on the serving host
(`proxmox-observability-debian:9090` Prometheus, `:9093` Alertmanager,
`:3100` Loki).

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
- **Forward Authentication Integration**: Per-vhost only (Grafana hybrid; budget,
  paperless, proxmox, truenas). Grafana sets `edge.apiBearerBypass` so
  `Authorization: Bearer` on `/api/*` skips oauth2-proxy
  ([adr/2026-11-05-grafana-api-bearer-bypass.md](../adr/2026-11-05-grafana-api-bearer-bypass.md)).
  There is no public Prometheus vhost. Keycloak has no forward-auth. See
  [adr/2026-08-29-oauth2-proxy-coverage.md](../adr/2026-08-29-oauth2-proxy-coverage.md).
  Eval fails if `fleet.apps.keycloak.edge.auth` is set, or if
  `apiBearerBypass` is set without `auth = "hybrid"`.
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
- **Layer 4 Proxy (`caddy-l4`)**: Custom built package containing the `caddy-l4` plugin to proxy UDP game traffic
  to `proxmox-applications-debian`:
  ```caddy
  layer4 {
    udp/:27960 {
      route {
        proxy udp/proxmox-applications-debian:27960
      }
    }
    udp/:30000 {
      route {
        proxy udp/proxmox-applications-debian:30000
      }
    }
  }
  ```
- **Admin Restrictions**: Requests to `/admin*` are blocked unless they originate from the Tailscale range
  `100.64.0.0/10`. This applies to **both** `vaultwarden.alexmayers.co.za` and `identity.alexmayers.co.za` — the
  Keycloak admin console was previously reachable from the public internet behind nothing but its own login form.
- **Admin API**: Caddy's own admin endpoint is bound to `127.0.0.1:2020` and is not opened on any interface.

## Alerting

Rules live in the `caddy` group in
[`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml). Caddy does not
export `caddy_tls_*`; 5xx is on
`caddy_http_request_duration_seconds_count{code=...}`. Dashboards: Caddy,
Caddy Hosts, Caddy standalone.

| Alert | Catches |
|---|---|
| `CaddyHigh5xxErrorRate` | 5xx above 5% of requests |
| `CaddyUpstreamUnhealthy` | `caddy_reverse_proxy_upstreams_healthy == 0` |
| `CaddyRequestErrors` | `caddy_http_request_errors_total` rising |
| `ImmichEdge502` | more than ten 502s in 5m for `immich.alexmayers.co.za` |
