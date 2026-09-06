# Caddy (internal load balancer)

**Host:** `proxmox-lb` · **Module:** [services/caddy-internal.nix](../../services/caddy-internal.nix)

## Overview

This is the second tier of the fleet's routing. The [edge Caddy](caddy.md) on `xcloud-caddy` terminates TLS and applies
authentication, then forwards nearly every vhost to `proxmox-lb:80` with the original `Host` header intact. This
instance reads that header and picks a backend.

Keeping the backend lists here rather than at the edge means adding or draining a replica is a change on one internal
host, and it does not require touching the internet-facing machine.

It listens on plain HTTP only. It is reachable exclusively over `tailscale0`; nothing here is exposed publicly.

## Ports

| Port   | Purpose                                                       |
|--------|---------------------------------------------------------------|
| `80`   | HTTP vhost routing for all edge-forwarded services            |
| `3902` | Garage S3 API — used by Loki, Mimir and Attic                 |
| `3903` | Garage admin /health — proxied to db-1/db-2                   |
| `3100` | Loki API — used by Grafana and Alloy                          |
| `9009` | Mimir query-frontend and write path                           |
| `9093` | Alertmanager                                                  |
| `8080` | Attic binary cache                                            |

UDP `27960` (OpenArena) and `30000` (Luanti) are forwarded to `proxmox-applications-1` using the `layer4` plugin.

## Backends and health checks

Every multi-backend vhost carries an active health check, so a replica that is listening but broken is removed from
rotation rather than serving errors:

| Route                    | Backends                                          | Policy        | Health check    |
|--------------------------|---------------------------------------------------|---------------|-----------------|
| `grafana`                | `proxmox-observability-{1,2}:3000`                | `cookie`      | `/api/health`   |
| `identity` (Keycloak)    | `proxmox-applications-{1,2}:7777`                 | `round_robin` | `/health/ready` on port `9000` |
| `tasks` (Vikunja)        | `proxmox-applications-{1,2}:3456`                 | `round_robin` | `/api/v1/info`  |
| `ntfy`                   | `proxmox-observability-{1,2}:2586`                | `first`       | `/v1/health`    |
| `:3902` (S3)             | `proxmox-db-{1,2}:3902`, probed on `:3903`        | `round_robin`, `lb_try_duration 0s` | `/health`       |
| `:3903` (Garage health)  | `proxmox-db-{1,2}:3903`                           | `round_robin` | `/health`       |
| `:3100` (Loki)           | `proxmox-observability-{1,2}:3100`                | `round_robin` | `/ready`        |
| `:9009` (Mimir)          | `proxmox-observability-{1,2}:9009`                | `round_robin` | `/ready`        |
| `:9093` (Alertmanager)   | `proxmox-observability-{1,2}:9093`                | `round_robin` | `/-/healthy`    |
| `:8080` (Attic)          | `proxmox-dev:8080`                                | (single)      | `/`             |

Attic backend is `attic-nar-proxy` on proxmox-dev `:8080`, which follows atticd's 307 to Garage
and returns 200 (Nix will not substitute a 307 with an empty body). This hop still rewrites any
leaked Location onto `:8080` and proxies `.chunk` with `flush_interval -1`. Multi-chunk NARs can
still truncate through this Caddy hop (`Transferred a partial file`), so deploys copy from
`http://proxmox-dev:8080/attic` rather than the LB.

Two routes have a health check but only one backend, which is deliberate:

- **`paperless`** &rarr; `proxmox-applications-1:28981` only. There is no replica.
- **`vaultwarden`** &rarr; `proxmox-applications-1:8222` only, checked on `/alive`.

The remaining routes (`jellyfin`, `immich`, `gitlab`, `registry`, `coder`, `budget`) are plain single-backend proxies
with no health check — there is one instance of each and nowhere to fail over to.

Two details worth knowing when debugging a backend that looks healthy but is out of rotation:

- Keycloak's health endpoint is on a **separate management port** (`health_port 9000`), not the traffic port `7777`.
- Garage's health endpoint is on the **admin port** `3903`, while the S3 API it guards is on `3902`.

Every health check sets `unhealthy_status 5xx` and `max_fails 1`, so one server error takes a backend out for the
`fail_duration` rather than continuing to serve failures. Port-based sites are bound as `http://:3100` (and the other
ports), not `http://proxmox-lb:3100`, so a request without that Host header still hits the reverse_proxy. When every
upstream is unhealthy the proxy returns 5xx, not an empty 200.

## Single point of failure

`proxmox-lb` is one VM, and both the edge and the observability stack route through it. If it is down:

- every public service except `proxmox` and `truenas` (those skip this host)
  returns an error at the edge
- Loki, Mimir and Attic lose object storage, because they address Garage through `proxmox-lb:3902`
- Grafana's datasources fail, because they point at `proxmox-lb`

Alloy's write-ahead log absorbs a short outage without losing logs, but the blast radius is wide. Making this tier
redundant is a topology change, not a configuration change.
