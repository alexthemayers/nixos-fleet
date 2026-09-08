# Memory limits

Cgroup caps and other large heaps, so host RAM is a sum. Add a row when you
set or change `MemoryMax`, `MemoryHigh`, or `GOMEMLIMIT`. Agent constraint:
`.cursor/rules/memory-limits.mdc`.

## Host RAM (known targets)

| Host | RAM target | Notes |
|------|------------|-------|
| `proxmox` (hypervisor) | 94 GiB physical | Guest commit is the sum below. `ProxmoxMemoryPressureHigh`/`Critical` and `ProxmoxHostSwapping` guard the host. Do not raise a guest without checking `MemAvailable`. |
| `truenas-scale` (VM 100) | 24 GiB | ZFS ARC for media **and** guest-root NFS ([nfs-vm-roots](adr/2026-09-07-nfs-vm-roots.md)). |
| `proxmox-applications-1` (VM 101) | 12 GiB | Jellyfin, Immich, Keycloak, Vikunja, Paperless. Live RSS ~5 GiB; transcode spikes stay here. |
| `proxmox-applications-2` (VM 102) | 12 GiB | GitLab + registry. Several `bundle` workers ~1 GiB each. |
| `proxmox-observability` (VM 103) | 8 GiB | Grafana, Prometheus, Loki, Mimir, ntfy, Garage. Caps below. |
| `proxmox-dev` (VM 106) | 12 GiB | Attic, Coder, runner. Idle ~2 GiB; fills use page cache. Was 16 GiB. |
| `xcloud-postgres` | 1 GiB | [ADR](adr/2026-09-04-xcloud-postgres-1g.md) |
| `xcloud-caddy` | cloud default | Edge only; no cgroup sum on this table. |

Guest commit is **68 GiB** (24+12+12+8+12). Host leftover is for PVE, not
another VM.

## systemd limits

| Unit | Hosts | MemoryHigh | MemoryMax | Other | Why |
|------|-------|------------|-----------|-------|-----|
| `alloy` | fleet default | 384M | 512M | | Loki outage must not OOM the box ([monitoring.md](monitoring.md)) |
| `alloy` | `xcloud-postgres` | 320M | 384M | `GOMEMLIMIT=192MiB` | Below fleet 512M; 160M reclaim-stormed the disk ([ADR](adr/2026-09-08-xcloud-postgres-alloy-cap.md)) |
| `mimir` | obs-1 | 2G | 2.5G | | All-in-one compaction |
| `loki` | obs-1 | 640M | 768M | | Leave room for Mimir + Grafana + Garage |
| `prometheus` | obs-1 | 896M | 1G | | Agent + remote_write |
| `grafana` | obs-1 | — | 768M | | |
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
| Redis `maxmemory` | `xcloud-postgres` | 16+16+32 MB | oauth2-proxy, vikunja, paperless; `allkeys-lru` ([redis.md](services/redis.md)) |
| Keycloak JVM | apps-1 | unbounded | `cache=local`; no `-Xmx`. Live RSS ~540 MiB. |
