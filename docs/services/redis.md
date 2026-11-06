# Redis

**Host:** `xcloud-postgres` · **Module:** [services/redis.nix](../../services/redis.nix)

## Overview

Three Redis instances run on the database VM, enabled when
`fleet.apps.redis.host` matches this host
([`fleet/apps/redis.nix`](../../fleet/apps/redis.nix)). They are not a
replica set. Each instance is a dedicated database for one consumer, so a
flush or a restart of oauth2-proxy sessions cannot take Vikunja or
Paperless with it.

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
`tailscale0` only: `6379`, `6380`, `6381`, and `9121`/`9122`/`9123`
(one redis exporter per instance).

Each instance has `maxmemory` (`16mb` oauth2-proxy and vikunja, `32mb`
paperless) and `maxmemory-policy allkeys-lru` so a runaway keyspace cannot
starve Postgres on the 1 GiB hub
([ADR](../adr/2026-09-04-xcloud-postgres-1g.md),
[memory.md](../memory.md)).

A probe without a password must return `NOAUTH Authentication required.`

## Exporter

Three `prometheus-redis-exporter-*` units on `xcloud-postgres`, each with its
own sops `EnvironmentFile` (`REDIS_ADDR` + `REDIS_PASSWORD`) so the password
never enters the Nix store. Scraped as `job="redis"` with
`redis_instance` = `oauth2-proxy` / `vikunja` / `paperless`. Each unit is
`MemoryMax = 32M` ([memory.md](../memory.md)).

## Alerting

Dashboard: `fleet-redis`.

| Alert | Catches |
|---|---|
| `RedisDown` | `redis_up == 0` on any instance |
| `RedisMemoryHigh` | used / maxmemory above 90% |
| `RedisRejectedConnections` | rejected connections in 15m |

Rules: [`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml) `redis`
group. Evictions under `allkeys-lru` are expected and are not paged.
