# Mimir

Mimir is **not running**. Prometheus on `proxmox-observability-debian`
keeps 62 days of TSDB on local disk
([adr/2026-11-04-local-metrics-and-logs.md](../adr/2026-11-04-local-metrics-and-logs.md)).
VM 103 was destroyed on 2026-11-04.

Governing placement ADR (historical):
[2026-09-07-observability-monolith.md](../adr/2026-09-07-observability-monolith.md).
Series-headroom decision (superseded for live scrapes by local Prometheus):
[2026-09-05-mimir-series-headroom.md](../adr/2026-09-05-mimir-series-headroom.md).

Do not treat old Mimir runbook text as live. Live metrics:
[prometheus.md](prometheus.md),
[proxmox-observability-debian.md](proxmox-observability-debian.md).
