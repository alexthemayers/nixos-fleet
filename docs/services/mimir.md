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
`ingestion_burst_size = 100000`, `max_global_series_per_user = 600000`) so a
scrape spike is a 429, not an OOM.

## Series cap

`max_global_series_per_user` is **enforced per ingester as `cap / ingester
count`**, not against the fleet total. With two ingesters and a 600000 cap
each one allows 300000. Series shard by hash and the shard is not even, so
the busier ingester reaches its share while the global total still looks
comfortable — that is the failure this cap produces in practice, and it is
why the alerts below are per ingester rather than on a fleet sum.

Reaching the share is a cliff, not a throttle. The ingester rejects **every
new series** with `err-mimir-max-series-per-user`, returned to the writer as
a 400. That means:

- Rejected samples do **not** appear in `cortex_discarded_samples_total`.
  Only `ingestion_rate` / `ingestion_burst_size` discards land there.
- The **ruler** writes its rule results through the same path, so rule
  evaluation starts failing at the same moment. Alerting degrades exactly
  when it is most needed.
- Prometheus reports it as `PrometheusRemoteStorageFailures`, which names the
  symptom and not the cause.

`MimirTenantSeriesHeadroomLow` (80%) and `MimirTenantSeriesLimitAtCap` (98%)
page on the cause. Both divide by
`cortex_ingester_local_limits{limit="max_global_series_per_user"}`, which is
the cap already divided by the ingester count, so they follow the configured
value without being edited alongside it.

### When headroom runs low

Cut cardinality first; it is free, and a smaller working set is faster to
query and compact. Find the growth:

```promql
topk(20, count by (__name__) ({__name__!=""}))
```

Drop names nothing reads with `metric_relabel_configs` in
[`services/prometheus.nix`](../../services/prometheus.nix) (`dropMetrics`).
Check for a rule, dashboard `expr`, and alert first — a Grafana panel can
carry a stale name in its legacy `"metric"` field while querying something
else, so grep the `expr` values rather than the whole dashboard JSON.

Raise the cap only after checking Mimir's RSS against `MemoryMax`, and raise
the VM's RAM before the cap if there is no room. Sizing history and the
measured per-series cost are in
[mimir-series-headroom ADR](../adr/2026-09-05-mimir-series-headroom.md).

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
`Content-Length` then an empty or truncated body) do **not** unblock
compaction with `no-compact-mark.json` alone. Store-gateway and cleanup still
read every advertised `index`. If both Garage replicas fail the same GET after
retries, delete the whole ULID prefix. Do not `garage repair blocks`. See
[garage-metadata-resync.md](../runbooks/garage-metadata-resync.md) and
[2026-09-05-mimir-delete-lost-blocks.md](../adr/2026-09-05-mimir-delete-lost-blocks.md).

`stopIfChanged` / `restartIfChanged` are false for the same tailscaled-during-switch reason as Loki.

The ruler evaluates local files from `/etc/mimir-rules` and sends to both
Alertmanager instances. Garage cluster alerts are in the `garage` group
([garage.md](garage.md#alerting)).

## Ruler meta-monitoring

Every alert in the fleet is evaluated by this ruler, so a ruler that fails,
stalls, or cannot reach Alertmanager takes all alerting with it — and does so
silently, because a broken rule does not page about itself. The `mimir-ruler`
group watches for that:

| Alert | Catches |
|---|---|
| `MimirRulerEvaluationFailing` | a rule that cannot be evaluated or whose write is rejected |
| `MimirRulerMissingEvaluations` | a group slower than its interval, so alerts are late |
| `MimirRulerConfigReloadFailed` | the rules file was rejected; stale rules are running |
| `MimirRulerNoRulesLoaded` | no ruler has any rules at all |
| `MimirRulerNotDeliveringAlerts` | alerts fire but never reach Alertmanager |
| `MimirRulerNoAlertmanagers` | nothing to notify |
| `MimirRulerWriteRequestsFailing` | recording rules stop producing series |

`reason="user"` on an evaluation failure means the rule or its write: a bad
expression, or a recording-rule result rejected on ingest — the series cap
above produces exactly this. `reason="operator"` is server-side and points at
Mimir or Garage instead.

Rule groups shard across the two rulers, so these aggregate by `rule_group`
rather than `instance`. A group moving between nodes is normal.

### These are not the `prometheus_*` alerts

Prometheus runs with `--enable-feature=agent` and evaluates **no rules**:
`/api/v1/rules` is empty and `prometheus_rule_evaluation_failures_total`,
`prometheus_rule_group_iterations_missed_total`, and
`prometheus_notifications_*` are never exported. `PrometheusRuleFailures`,
`PrometheusMissingRuleEvaluations`, and
`PrometheusErrorSendingAlertsToSomeAlertmanagers` therefore cannot fire. They
are kept to stay diffable against the upstream prometheus-operator set and are
commented as inert; do not read them as coverage. The `cortex_prometheus_*`
and `cortex_ruler_*` metrics above are the ones with data.

### Checking the rules themselves

`services/mimir-rules.nix` throws at **eval** time on a duplicate alertname, a
missing `summary`/`description`, or a missing `for`, so `make lint` catches
those. It is an eval-time throw rather than a promtool derivation because
`make lint` and CI both run `nix flake check --no-build`, which would evaluate
a derivation and never build it.

PromQL parsing and annotation templates need the binary:

```bash
make check-mimir-rules   # on proxmox-dev; the rules file is x86_64-linux
```

## Caddy

Internal Caddy listens on `:9009` (any Host) with `/ready` health checks and `unhealthy_status 5xx`.
