# ADR: xcloud-postgres is sized for 1 GiB RAM

**Status:** accepted (2026-09-04)

## Context

`xcloud-postgres` is an accepted SPOF
([four hubs](2026-08-29-four-hubs.md)). It runs PostgreSQL 17, PgBouncer,
three Redis instances, Alloy, and the usual exporters on a cloud VM.

On the live 1.9 GiB / 1 CPU instance, PostgreSQL was ~820 MiB
(`shared_buffers` 512 MB plus ~40 idle backends), Alloy ~265 MiB, and
journald ~100 MiB. 126 MiB of disk swap was in use while ~650 MiB was
still `MemAvailable` (page cache). GitLab had 25 client connections
mapped to 10 backends against `pool_size=50`. The `postgres` auth_query
pool sat at five idle backends because `default_pool_size=20`.

That working set does not fit in 1 GiB without swap as the normal path.

## Decision

Size the hub for **1 GiB RAM / 1 CPU**:

- PostgreSQL: `shared_buffers=128MB`, `work_mem=4MB`, `max_connections=70`,
  JIT and huge pages off, one autovacuum worker, no parallel gather.
- PgBouncer: small per-database pools, `server_idle_timeout=60s`.
  Attic stays session pooling with a cap of 20 (a cap of 5 caused
  `query_wait_timeout` on fills). PostgreSQL `max_connections=70` is the
  backstop above the pool-cap sum.
- Alloy on this host only: `GOMEMLIMIT=96MiB`, `MemoryMax=160M`. Fleet
  default `512M` stays for the 4 GiB observability VMs.
- Cloud VMs: zram first, 2 GiB disk swap last, `vm.swappiness=10`,
  journald `SystemMaxUse=64M`, Nix `download-buffer-size` 64 MiB.

Do not cut the Attic session cap to save idle RAM. Fill spikes may use
zram.

## Consequences

Idle RAM is dominated by ~20–30 Postgres backends plus Alloy, not by
`shared_buffers`. Immich (~950 MB) will miss cache more often; that is
the 1 GiB tradeoff. After switch, Postgres must restart for
`shared_buffers` / `max_connections`. Check `free -h` and `SHOW POOLS`
before shrinking the provider VM.
