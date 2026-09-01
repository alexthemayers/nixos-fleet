# Mimir Metrics Aggregation Service Configuration

This document describes the **Grafana Mimir** deploy in `nixos-fleet`.

## Overview

Mimir runs all-in-one (`target = all`) on **`proxmox-observability-1`** and **`proxmox-observability-2`**. Prometheus
agents remote_write to `localhost:9009`; Grafana queries through `proxmox-lb:9009/prometheus`. There is no Pi member.

## Networking and ports

Allowed on `tailscale0` only:

- **`9009`**: HTTP (push, query, `/ready`).
- **`9096`**: gRPC.
- **`7947`**: memberlist gossip (TCP/UDP).

## Secrets

- **`mimir/s3_access_key`** and **`mimir/s3_secret_key`**: Garage credentials for the `mimir` bucket.

Rendered into `mimir.env` and loaded as `EnvironmentFile`.

## Storage

TSDB blocks go to Garage bucket `mimir` via `proxmox-lb:3902` (round-robin to
db-1 and db-2). Local WAL/cache is `/var/lib/mimir/tsdb`. If one node 404s
keys the other has, repair Garage
([garage-metadata-resync.md](../runbooks/garage-metadata-resync.md)); do not
pin this endpoint at db-1.

## Clustering

Same oneshot as Loki: `mimir-cluster-env.service` writes `/run/mimir-cluster.env` before the daemon starts. Do not use
`ExecStartPre` to create that `EnvironmentFile`.

`ingester.ring.replication_factor = 1`. Two ingesters with RF=2 stopped writes whenever one obs node was down. Garage
already stores two copies of blocks.

`MemoryMax = 2.5G` / `MemoryHigh = 2G` so all-in-one compaction can finish on the
4–6 GiB guests. Ingestion limits are finite (`ingestion_rate = 25000`,
`ingestion_burst_size = 100000`, `max_global_series_per_user = 300000`) so a
scrape spike is a 429, not an OOM.

`bucket_store.bucket_index.max_stale_period = 24h` so a 24h Grafana range
query does not 500 while the compactor is still deleting ghost Garage blocks
(`limits.compactor_partial_block_deletion_delay = 4h`, the minimum Mimir will honour). Grafana
shows Mimir's HTTP 500 as "response from prometheus couldn't be parsed" —
that text is the Prometheus plugin, not a broken JSON body. Instant queries
(`query=up`) still hit the ingesters and succeed.

S3 uses `bucket_lookup_type = path` (Garage is path-style, same idea as Loki's
`s3forcepathstyle`). Compactor `data_dir`, `compaction_interval` (15m), and
`cleanup_interval` are set explicitly; cleanup is what rewrites the bucket
index. Prometheus scrapes `:9009`. `MimirCompactorFailed` only pages on
`reason="error"`; `reason="shutdown"` is context cancel (process stop, or a
sibling GET hitting a ghost Garage object). `MimirCompactorHasNotRun` still
pages if no run completes for two hours.

Ghost blocks (object metadata exists, GET of `index` / `chunks/000001` returns
`Content-Length` then an empty body) unblock compaction by writing
`anonymous/<ulid>/no-compact-mark.json` with `reason=critical`. Do not
`garage repair blocks` for that; see
[garage-metadata-resync.md](../runbooks/garage-metadata-resync.md).

`stopIfChanged` / `restartIfChanged` are false for the same tailscaled-during-switch reason as Loki.

The ruler evaluates local files from `/etc/mimir-rules` and sends to both Alertmanager instances.

## Caddy

Internal Caddy listens on `:9009` (any Host) with `/ready` health checks and `unhealthy_status 5xx`.
