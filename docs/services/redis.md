# Redis

**Host:** `xcloud-postgres` · **Module:** [services/redis.nix](../../services/redis.nix)

## Overview

Three Redis instances run on the database VM, enabled by
`fleet.services.redis.enable` in [hosts/xcloud-postgres/configuration.nix](../../hosts/xcloud-postgres/configuration.nix).
They are not a replica set. Each instance is a dedicated database for one
consumer, so a flush or a restart of oauth2-proxy sessions cannot take Vikunja
or Paperless with it.

| Instance       | Port | Consumer                         |
|----------------|------|----------------------------------|
| `oauth2-proxy` | 6379 | oauth2-proxy sessions on `xcloud-caddy` |
| `vikunja`      | 6380 | Vikunja on apps-1 and apps-2     |
| `paperless`    | 6381 | Paperless on apps-1              |

## Authentication and firewall

Each instance has `requirePassFile` and `protected-mode = yes`. The passwords
live in sops (`redis/oauth2_proxy_password`, `redis/vikunja_password`,
`redis/paperless_password`) and `restartUnits` bounces the matching
`redis-*.service` when the secret changes.

They bind `0.0.0.0` because clients reach them over Tailscale and the
`tailscale0` address is not known at build time. The nftables allow-list is
`tailscale0` only: `6379`, `6380`, `6381`, and `9121` (redis exporter).

A probe without a password must return `NOAUTH Authentication required.`

## Exporter

`prometheus-redis-exporter` authenticates as the oauth2-proxy instance (the
first password is reused for scrape). It is scraped from the observability
hosts over the tailnet.
