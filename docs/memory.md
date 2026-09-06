# Memory limits

Cgroup caps and other large heaps, so host RAM is a sum. Add a row when you
set or change `MemoryMax`, `MemoryHigh`, or `GOMEMLIMIT`. Agent constraint:
`.cursor/rules/memory-limits.mdc`.

## Host RAM (known targets)

| Host | RAM target | Notes |
|------|------------|-------|
| `proxmox-observability-1`, `-2` | 4–6 GiB | Mimir, Loki, Grafana, Prometheus, Alloy ([mimir.md](services/mimir.md), [loki.md](services/loki.md)) |
| `xcloud-postgres` | 1 GiB | [ADR](adr/2026-09-04-xcloud-postgres-1g.md) |

Other hosts are not sized from this table yet. Fill them in when a limit
or a RAM change lands.

## systemd limits

| Unit | Hosts | MemoryHigh | MemoryMax | Other | Why |
|------|-------|------------|-----------|-------|-----|
| `alloy` | fleet default | 384M | 512M | | Loki outage must not OOM the box ([monitoring.md](monitoring.md)) |
| `alloy` | `xcloud-postgres` | 112M | 160M | `GOMEMLIMIT=96MiB` | 1 GiB hub override |
| `mimir` | obs-1, obs-2 | 2G | 2.5G | | All-in-one compaction |
| `loki` | obs-1, obs-2 | 640M | 768M | | Leave room for Mimir + Grafana |
| `prometheus` | obs-1, obs-2 | 896M | 1G | | Agent + remote_write |
| `grafana` | obs-1, obs-2 | — | 768M | | |
| `prometheus-node-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-postgres-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-pgbouncer-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-redis-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-systemd-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-smokeping-exporter` | `xcloud-postgres` | — | 64M | | 1 GiB hub |

## Large heaps without a cgroup cap

| Consumer | Hosts | Size | Notes |
|----------|-------|------|-------|
| PostgreSQL `shared_buffers` | `xcloud-postgres` | 128MB | Plus backends; `max_connections=70` ([postgres.md](services/postgres.md)) |
