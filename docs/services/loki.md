# Loki Log Aggregation Service Configuration

This document describes the **Grafana Loki** deploy in `nixos-fleet`.

## Overview

Loki runs on **`proxmox-observability-debian`** with a filesystem store
and 62 days of retention. Clients (Vector, Grafana) talk to
`proxmox-observability-debian:3100` (Grafana on loopback). There is no
memberlist ring.

```bash
curl -sS http://127.0.0.1:3100/memberlist | grep -E 'Members:|loki-v4-'
# Members: 1, name loki-v4-proxmox-observability-* only
curl -sf http://127.0.0.1:3100/ready
```

`auth_enabled = false`. Loki's default is multi-tenant (`true`); Grafana's provisioned datasource and Vector's
Loki sink do not set `X-Scope-OrgID`, so queries and pushes fail with 401 `no org id`. This matches Mimir
(`multitenancy_enabled = false`). Tailscale is the perimeter.

## Networking and ports

Allowed on `tailscale0` only:

- **`3100`**: HTTP (push, query, `/ready`).
- **`9095`**: gRPC.
- **`7946`**: memberlist gossip (TCP/UDP).

## Secrets

- **`loki/s3_access_key`** and **`loki/s3_secret_key`**: Garage credentials for the `loki` bucket.

Rendered into `loki.env` (sops template) and loaded as `EnvironmentFile`.

## Storage

Chunks and the TSDB index go to Garage bucket `loki` via
`proxmox-observability:3902` (schema `v13`, 31 day retention). Garage
itself is RF=1 on `proxmox-observability`. A holed `*-compactor-*.tsdb.gz` under
`index/index_NNNNN/fake/` aborts compact-tables (`unexpected EOF`) until
that key is deleted
([garage-metadata-resync.md](../runbooks/garage-metadata-resync.md)).

## Clustering

Loki on `proxmox-observability-debian` is a single process. There is no
memberlist ring and no `loki-cluster-env` oneshot. Historical NixOS
`fleet.clusterEnv` is gone
([how-to-dynamic-tailscale.md](../how-to-dynamic-tailscale.md)).


## Alerting

Rules live in the `loki` group in
[`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml).
Dashboard: `fleet-loki`. Vector scrape is `VectorTargetDown` on
`fleet-vector` ([monitoring.md](../monitoring.md)).

| Alert | Catches |
|---|---|
| `LokiTargetDown` | scrape of `:3100` failed |
| `LokiRingWrongSize` | ACTIVE members ≠ 1 on ingester/distributor/scheduler/compactor |
| `LokiRingMemberUnhealthy` | a ring member is `UNHEALTHY` |
| `LokiRequestErrors` | HTTP 5xx rate above 5% on a route |
| `LokiS3Errors` | Garage 5xx rate above 5%, or more than 0.5 5xx/s |
| `LokiCompactorFailed` | compact-tables `status="failure"` increased in 1h |
| `LokiCompactorHasNotRun` | no successful compact-tables in 2h |
| `LokiRetentionFailed` | apply-retention `status="failure"` increased in 1h |
| `LokiRetentionNotApplied` | no successful apply-retention in 6h |
| `LokiIngesterFlushFailures` | chunk flushes failing |
| `LokiIngesterFlushBacklog` | flush queue averaged above 10 over 15m |
| `LokiIndexUploadsStalled` | no successful tsdb-shipper upload in 1h |
| `LokiWALDiskFull` | WAL writes failing on a full disk |
| `LokiWALCorruption` | `loki_ingester_wal_corruptions_total` increased |
| `LokiNoLogsReceived` | distributor accepting under 1 line/s |
| `LokiIngestionRateNearLimit` | above 70% of `limits_config.ingestion_rate_mb` |
| `LokiQueryPathDisconnected` | frontend has no scheduler, or scheduler no querier |
| `LokiMemoryNearLimit` | RSS above 85% of `MemoryMax` |
| `LokiClientDrops` | Vector dropped or failed Loki writes (`vector_component_discarded_events_total` / `vector_component_errors_total`, `component_id=loki`) |
| `VectorTargetDown` | scrape of Vector `:9598` failed ([monitoring.md](../monitoring.md)) |
| `LokiPanic` | `loki_panic_total` increased |

`LokiRingWrongSize` is the leftover-member check: a retired obs-2 or
Loki raises ACTIVE above 1. Compactor last-success uses `max()` because
only the elected member exports a non-zero timestamp.

The three quiet failures these were added for, none of which shows up as an
error anywhere else:

- **Nothing arriving.** `LokiNoLogsReceived`. Loki up, scrape green, Explore
 empty. The floor over 7 days is 18 lines/s, so under 1/s is unambiguous.
- **Retention not running.** `LokiRetentionFailed` / `LokiRetentionNotApplied`.
 Retention shares the compact-tables loop, so the holed Garage object that
 stalled compaction also gave 94 retention failures and no successes in 24h:
 nothing expired for ten days. The last-success gauge is deliberately
 unguarded, because 0 (never succeeded since start) is the case to catch.
- **Index not reaching Garage.** `LokiIndexUploadsStalled`. Chunks keep
 flushing, so writes look healthy; the index is what a query needs, and
 uploads have never dropped below 50/h in 7 days.

`LokiQueryPathDisconnected` watches the `frontend.instance_interface_names`
landmine above from the scheduler side only:
`loki_querier_query_frontend_clients` is 0 by design here, because queriers
dial the scheduler rather than the frontend.

`LokiMemoryNearLimit` compares RSS against the Loki `MemoryMax` listed in
[memory.md](../memory.md) (`go_gc_gomemlimit_bytes` is `MaxInt64`, so the
cgroup number is the only one available). Config lives in
[`roles/observability`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/).
With `Restart=always` an OOM is a restart that drops WAL-buffered logs,
not an outage, which is why it otherwise passes unnoticed.
