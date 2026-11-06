# Memory limits

Cgroup caps and other large heaps, so host RAM is a sum. Add a row when you
set or change `MemoryMax`, `MemoryHigh`, or `GOMEMLIMIT`. Agent constraint:
`.cursor/rules/memory-limits.mdc`.

## Host RAM (known targets)

| Host | RAM target | Notes |
|------|------------|-------|
| `proxmox` (hypervisor) | 94 GiB physical | Guest commit is the sum below. `ProxmoxMemoryPressureHigh`/`Critical` and `ProxmoxHostSwapping` guard the host. Do not raise a guest without checking `MemAvailable`. |
| `truenas-scale` (VM 100) | 24 GiB | ZFS ARC for media **and** guest-root NFS ([nfs-vm-roots](adr/2026-09-07-nfs-vm-roots.md)). |
| `proxmox-applications-debian` (VM 109) | 12 GiB | Apps. [ADR](adr/2026-11-01-debian-applications-guest.md). |
| `proxmox-gitlab-debian` (VM 110) | 12 GiB | Debian GitLab + registry caches. Omnibus `gitlab-ce` 19.0.4. |
| `proxmox-observability-debian` (VM 111) | 8 GiB | Prometheus, Loki, Grafana, ntfy. [ADR](adr/2026-11-04-debian-observability-guest.md). |
| `proxmox-dev-debian` (VM 112) | 16 GiB | GitLab runner and the x86 builder. Answers as `proxmox-dev`. Podman service cap 14 GiB. |
| `xcloud-postgres` | 1 GiB | [ADR](adr/2026-09-04-xcloud-postgres-1g.md) |
| `xcloud-caddy` | cloud default | Edge only; no cgroup sum on this table. |

VMs 101, 102, 103, and 106 were destroyed on 2026-11-04. Their RAM is
no longer part of the guest commit.

## systemd limits

| Unit | Hosts | MemoryHigh | MemoryMax | Other | Why |
|------|-------|------------|-----------|-------|-----|
| `vector` | fleet default, `proxmox-applications-debian`, `proxmox-gitlab-debian` | 192M | 256M | | Loki outage is a 256 MiB disk buffer; cap RAM ([monitoring.md](monitoring.md)). The Debian guests set it in `fleet.debian_guest.monitoring` |
| `vector` | `xcloud-postgres` | 96M | 128M | | Below fleet 256M; Alloy's Go heap is gone ([ADR](adr/2026-09-08-vector-replaces-alloy.md)) |
| `loki` | `proxmox-observability-debian` | 640M | 768M | | Filesystem store, 62 days |
| `prometheus` | `proxmox-observability-debian` | 2G | 2.5G | | Local TSDB, 62 days. Took the Mimir cap |
| `grafana` | `proxmox-observability-debian` | 1G | 1G | | Grafana 13 sat near 720 MiB after provisioning. 512M MemoryHigh stalled the accept loop (`mem_cgroup` high events) and the UI stopped answering. Host had ~6 GiB free |
| `prometheus-node-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-postgres-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-pgbouncer-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-redis-exporter-oauth2-proxy` | `xcloud-postgres` | — | 32M | | 1 GiB hub; one exporter per Redis |
| `prometheus-redis-exporter-vikunja` | `xcloud-postgres` | — | 32M | | 1 GiB hub |
| `prometheus-redis-exporter-paperless` | `xcloud-postgres` | — | 32M | | 1 GiB hub |
| `prometheus-systemd-exporter` | `xcloud-postgres` | — | 48M | | 1 GiB hub |
| `prometheus-smokeping-exporter` | `xcloud-postgres` | — | 64M | | 1 GiB hub |
| `radarr` | apps-1 | 768M | 1G | | 384-movie library refresh sat at 372/384M |
| `sonarr` | apps-1 | 768M | 1G | | 53-series refresh sat at 340/384M |
| `prowlarr` | apps-1 | 512M | 768M | | Indexer proxy; no media mount |
| `qbittorrent` | apps-1 | 640M | 1G | | Download client; live RSS was ~40M at 512M cap |
| `flaresolverr` | apps-1 | 1G | 2G | | Chromium session-not-created at 1G on 1337x |
| `bazarr` | apps-1 | 384M | 512M | | Subtitle downloads; no Chromium |
| `immich-server` | `proxmox-applications-debian` | 1536M | 2G | | Nest API + microservices; live peak ~1.5G |
| `immich-machine-learning` | `proxmox-applications-debian` | 3G | 4G | | OpenVINO on `renderD128`. Model load previously sat on a 3G cap. Idle CPU RSS ~300 MiB; host had ~5.8 GiB available |
| `jellyfin` | `proxmox-applications-debian` | 3G | 3G | | 4K HDR QSV transcode. 768M/1536M stalled in `mem_cgroup_handle_over_high` with no segments written. Idle RSS ~500M |
| `keycloak` | `proxmox-applications-debian` | 1G | 1536M | | JVM; live RSS ~700M |
| `vaultwarden` | `proxmox-applications-debian` | 128M | 256M | | |
| `vikunja` | `proxmox-applications-debian` | 192M | 384M | | |
| `actual` | `proxmox-applications-debian` | 256M | 512M | | |
| `paperless-webserver` | `proxmox-applications-debian` | 384M | 512M | | |
| `paperless-consumer` | `proxmox-applications-debian` | 256M | 384M | | |
| `paperless-task-queue` | `proxmox-applications-debian` | 384M | 512M | | |
| `paperless-scheduler` | `proxmox-applications-debian` | 256M | 384M | | |
| `openarena-server` | `proxmox-applications-debian` | 256M | 512M | | |
| `luanti-server` | `proxmox-applications-debian` | 384M | 512M | | Mineclonia |

## Large heaps without a cgroup cap

| Consumer | Hosts | Size | Notes |
|----------|-------|------|-------|
| PostgreSQL `shared_buffers` | `xcloud-postgres` | 128MB | Plus backends; `max_connections=70` ([postgres.md](services/postgres.md)) |
| Redis `maxmemory` | `xcloud-postgres` | 16+16+32 MB | oauth2-proxy, vikunja, paperless; `allkeys-lru` ([redis.md](services/redis.md)) |
| GitLab `nixos/nix` job (Nix eval) | `proxmox-dev-debian` | 12 GiB container, 3 CPUs, no swap | One job can use the headroom. The Podman service is capped at 14 GiB. Jobs stay serialized via `resource_group: proxmox-dev-nix`. |
