# Memory limits

Cgroup caps and other large heaps, so host RAM is a sum. Add a row when you
set or change `MemoryMax`, `MemoryHigh`, or `GOMEMLIMIT`. Agent constraint:
`.cursor/rules/memory-limits.mdc`.

## Host RAM (known targets)

| Host | RAM target | Notes |
|------|------------|-------|
| `proxmox` (hypervisor) | 94 GiB physical | Guest commit is the sum below. `ProxmoxMemoryPressureHigh`/`Critical` and `ProxmoxHostSwapping` guard the host. Do not raise a guest without checking `MemAvailable`. |
| `truenas-scale` (VM 100) | 24 GiB | ZFS ARC for media **and** guest-root NFS ([nfs-vm-roots](adr/2026-09-07-nfs-vm-roots.md)). |
| `proxmox-applications-1` (VM 101) | 12 GiB | Jellyfin, Immich, Keycloak, Vikunja, Paperless, *arr, FlareSolverr. Live RSS ~5 GiB before *arr; transcode spikes stay here. Chromium on FlareSolverr is capped at 1G. |
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
| `vector` | fleet default | 192M | 256M | | Loki outage is a 256 MiB disk buffer; cap RAM ([monitoring.md](monitoring.md)) |
| `vector` | `xcloud-postgres` | 96M | 128M | | Below fleet 256M; Alloy's Go heap is gone ([ADR](adr/2026-09-08-vector-replaces-alloy.md)) |
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
| `radarr` | apps-1 | 320M | 384M | | Servarr UI + library match ([media-automation.md](services/media-automation.md)) |
| `sonarr` | apps-1 | 320M | 384M | | Same |
| `prowlarr` | apps-1 | 320M | 384M | | Indexer proxy; no media mount |
| `qbittorrent` | apps-1 | 448M | 512M | | Download client; raise only after live RSS vs cap |
| `flaresolverr` | apps-1 | 768M | 1G | | Headless Chromium for Cloudflare indexers |

## Large heaps without a cgroup cap

| Consumer | Hosts | Size | Notes |
|----------|-------|------|-------|
| PostgreSQL `shared_buffers` | `xcloud-postgres` | 128MB | Plus backends; `max_connections=70` ([postgres.md](services/postgres.md)) |
| Redis `maxmemory` | `xcloud-postgres` | 16+16+32 MB | oauth2-proxy, vikunja, paperless; `allkeys-lru` ([redis.md](services/redis.md)) |
| GitLab `nixos/nix` job (Nix eval) | `proxmox-dev` | ~one NixOS config | Serialized via `resource_group: proxmox-dev-nix`. No cgroup cap on the runner. `KernelOOMKills` pages if this slips. |
