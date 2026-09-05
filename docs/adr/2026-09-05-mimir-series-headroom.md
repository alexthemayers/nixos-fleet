# ADR: Mimir series headroom comes from cardinality, then cap

**Status:** accepted (2026-09-05)

## Context

`limits.max_global_series_per_user = 300000` was set after unbounded ingestion
turned a scrape spike into an OOM. The number was chosen before anything
measured what a series actually costs on these guests.

On 2026-09-05 the fleet reached 274850 in-memory series and
`proxmox-observability-2` sat at **exactly 150000**, its half of the cap. The
cap is enforced per ingester as `cap / ingester count`, so the global total
being under 300000 was irrelevant: series shard by hash, the shard was uneven
(obs-1 held 124850), and the busier ingester hit its share first. It then
rejected every new series with `err-mimir-max-series-per-user`.

Three things made that worse than a throttle:

- Rejections are returned to the writer as a 400 and are **not** counted in
  `cortex_discarded_samples_total`. Only `ingestion_rate` /
  `ingestion_burst_size` discards land there, so the obvious metric read zero
  while data was being lost.
- The **ruler** pushes rule results through the same path, so rule evaluation
  failed alongside ingestion. The observability stack degraded its own
  alerting at the moment it was needed.
- Mimir had exactly two alerts, both about the compactor. Nothing watched the
  caps. `PrometheusRemoteStorageFailures` fired on obs-2 and was accurate, but
  it names the symptom; nothing named the cause, and the condition had been
  running long enough to be visible for hours.

Memory was never the binding constraint. Measured during the incident, Mimir
held 0.53 GiB (obs-2, at 150000 series) and 0.59 GiB (obs-1, at 124850)
against `MemoryMax = 2.5G` on 5.8 GiB VMs with 3.6 GiB available. RSS at this
scale is dominated by base and query workload rather than series count — the
node with *fewer* series used *more* memory. The cap was roughly 4.5x more
conservative than the hardware required.

Cardinality was also genuinely bloated, and the top names were things nothing
reads:

| Series | Metric | Why it went |
|---|---|---|
| 15644 | `caddy_rate_limit_process_time_seconds_*` | latency histogram of the rate limiter's own bookkeeping, per zone and handler; no rule or dashboard |
| 10306 | `node_systemd_unit_state` | node-exporter's systemd collector duplicating the standalone systemd exporter, per unit per state |
| 7270 | `systemd_unit_{active_enter,active_exit,inactive_exit}_time_seconds` | per-unit timestamps; no reader |

The duplication needed care rather than removing a collector.
`ServiceDown` / `BackupJobFailed` read the standalone exporter's
`systemd_unit_state`, and the dashboards query `node_systemd_units` and
`node_systemd_socket_*`, which are per state rather than per unit and cheap.
Only `node_systemd_unit_state` had no `expr` behind it: the one dashboard
naming it does so in Grafana's legacy `"metric"` field while querying
`systemd_unit_state`.

## Decision

Headroom comes from cardinality first, cap second.

Drop the three groups above with `metric_relabel_configs` in
`services/prometheus.nix`, via a `dropMetrics` helper so the intent is one
list per scrape job. About 33220 series, near 12%. A name goes on the list
only after checking rules, alerts, and dashboard `expr` values — not merely
grepping the dashboard JSON, which matches legacy metadata fields.

`max_global_series_per_user` goes to **600000**: 300000 per ingester, roughly
1.1 GiB at the measured cost, still under `MemoryHigh`. That is real headroom
for both growth and shard skew rather than the ~10% the drops alone would
have bought. Raising it further requires more RAM first, not a bigger number.

`ingestion_rate` and `ingestion_burst_size` stay as they are. The 270363
`rate_limited` discards seen in the incident hour were a queued remote_write
replay draining after the Garage stall, not a steady-state rate problem; the
steady rate is 6275 samples/s against a 25000 limit.

Add three alerts to the `mimir` rule group: `MimirTenantSeriesLimitAtCap`
(98%, critical), `MimirTenantSeriesHeadroomLow` (80%, warning), and
`MimirSamplesDiscarded` (any sustained discard, warning). The two ratio
alerts divide by
`cortex_ingester_local_limits{limit="max_global_series_per_user"}`, which
Mimir exports as the cap already divided by the ingester count. They
therefore track the configured value without being edited alongside it, and
they are per ingester because that is how the cap is enforced.

## Consequences

Deploy is obs-1 and obs-2 only. `restartIfChanged = false` on Mimir, so
**restart `mimir.service` explicitly** after the switch or the old process
keeps the old cap; the same applies to `prometheus.service` for the drop
rules. Confirm with
`cortex_ingester_local_limits{limit="max_global_series_per_user"}` reading
300000 per ingester.

The dropped names disappear from Grafana for new data. Existing blocks keep
them until retention expires, so a historical panel over those names still
resolves for now and then stops. Nothing queried them, which is why they were
chosen, but a future dashboard cannot use them without removing the drop
rule.

`MimirSamplesDiscarded` will fire during any backlog replay after a Mimir or
Garage outage. That is intended: those samples are dropped rather than
retried, so a replay that loses data should be visible instead of silent.

The cap is now the second line of defence rather than the first. If headroom
alerts start firing regularly, the answer is a cardinality review, not a
reflexive increase — the caps exist because unbounded ingestion OOM'd these
guests once already.
