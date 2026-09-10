# Media automation (Radarr / Sonarr / Prowlarr / qBittorrent / FlareSolverr)

Acquisition, rename, and quality upgrades for Jellyfin **Movies** and
**Shows**. Module: [`services/media-automation`](../../services/media-automation).
Decision:
[2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md).
Pairing and library import:
[media-automation.md](../runbooks/media-automation.md).

Runs on **`proxmox-applications-1`** only, next to Jellyfin and
`/mnt/nfs/media`.

## Networking

Tailnet only. No Caddy vhost yet (no DNS). `openFirewall = false`; ports
are open on `tailscale0` only.

| UI | URL |
|---|---|
| Radarr | `http://proxmox-applications-1:7878` |
| Sonarr | `http://proxmox-applications-1:8989` |
| Prowlarr | `http://proxmox-applications-1:9696` |
| qBittorrent | `http://proxmox-applications-1:8081` |
| FlareSolverr | `http://proxmox-applications-1:8191` |

A later public vhost would be per-vhost oauth2-proxy on `xcloud-caddy`,
not fleet-wide forward-auth
([2026-08-29-oauth2-proxy-coverage](../adr/2026-08-29-oauth2-proxy-coverage.md)).

## Storage

qBittorrent saves under `/mnt/nfs/media/downloads` on the same NFS
dataset as `movies/` and `series/` so Radarr/Sonarr import is a
hardlink. Anime and documentaries are not root folders.

State under `/var/lib/{radarr,sonarr,prowlarr,qBittorrent}` is on the
VM root (NFS-backed qcow2). **Not** in git: API keys, indexer
credentials, download-client pairing, the WebUI password.

## No VPN

qBittorrent peer traffic leaves this VM's WAN path. There is no
gluetun or WireGuard killswitch
([2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md)).
A home-router inbound forward of the torrenting port is outside this
repo and only affects swarm connectivity.

## Memory

`MemoryMax` 384M on Radarr, Sonarr, and Prowlarr; 512M on qBittorrent;
1G on FlareSolverr (Chromium). Listed in [memory.md](../memory.md).
Check live RSS before raising.

## Alerting

`ServiceDown` / `ServiceCrashLooping` cover the five units. Blackbox
job `blackbox_http_internal` probes the five tailnet URLs;
`EndpointDown` uses `probe_success`. Dashboard: Grafana folder `fleet`,
`fleet-media-automation`. Queue depth and failed grabs need an exporter
(`exportarr`) this flake does not package.

## Out of scope

Bazarr, Lidarr, music. Anime and documentaries stay on
[jellyfin-metadata.md](../runbooks/jellyfin-metadata.md).
