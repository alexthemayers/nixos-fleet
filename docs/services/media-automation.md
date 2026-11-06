# Media automation (Radarr / Sonarr / Prowlarr / qBittorrent / FlareSolverr / Bazarr)

Acquisition, rename, quality upgrades, NFO, and text subtitles for
Jellyfin **Movies** and **Shows**. Live config:
[`fleet.debian_guest` apps](../../collections/ansible_collections/fleet/debian_guest/roles/apps/tasks/)
(`radarr.yml`, `sonarr.yml`, …). The Nix
`services/media-automation` tree was deleted with the Debian cutover.
Decisions:
[2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md),
[2026-09-11-arr-writes-nfo-and-refreshes-jellyfin](../adr/2026-09-11-arr-writes-nfo-and-refreshes-jellyfin.md),
[2026-09-11-bazarr-external-subs](../adr/2026-09-11-bazarr-external-subs.md).
Pairing and library import:
[media-automation.md](../runbooks/media-automation.md).

Runs on **`proxmox-applications-debian`** only, next to Jellyfin and
`/mnt/nfs/media`.

## Networking

Tailnet only. No Caddy vhost yet (no DNS). `openFirewall = false`; ports
are open on `tailscale0` only.

| UI | URL |
|---|---|
| Radarr | `http://proxmox-applications-debian:7878` |
| Sonarr | `http://proxmox-applications-debian:8989` |
| Prowlarr | `http://proxmox-applications-debian:9696` |
| qBittorrent | `http://proxmox-applications-debian:8081` |
| FlareSolverr | `http://proxmox-applications-debian:8191` |
| Bazarr | `http://proxmox-applications-debian:6767` |

A later public vhost would be per-vhost oauth2-proxy on `xcloud-caddy`,
not fleet-wide forward-auth
([2026-08-29-oauth2-proxy-coverage](../adr/2026-08-29-oauth2-proxy-coverage.md)).

## Storage

qBittorrent saves under `/mnt/nfs/media/downloads` on the same NFS
dataset as `movies/` and `series/` so Radarr/Sonarr import is a
hardlink. Anime and documentaries are not root folders.

Sonarr `-data` is `/mnt/nfs/media/arr-stack/sonarr/.config/NzbDrone`.
Radarr `-data` is `/mnt/nfs/media/arr-stack/radarr/.config/Radarr`.
Prowlarr, Bazarr, and qBittorrent use
`/mnt/nfs/media/arr-stack/{prowlarr,bazarr,qbittorrent}`. The Sonarr
and Radarr sqlite files are in those `.config` directories. Pointing
`-data` at the parent creates a new empty database and a fresh
`config.xml` beside them. **Not** in git: API keys, indexer
credentials, download-client pairing, the WebUI password, subtitle
provider logins.

Prowlarr full-syncs indexers to Radarr and Sonarr on `127.0.0.1`.
qBittorrent is the download client on all three (categories
`radarr` / `sonarr` / `prowlarr`). Same-host `*arr` calls skip
WebUI auth (`WebUI\LocalHostAuth=false`); the tailnet UI still
needs the password. Roots are `/mnt/nfs/media/movies` and
`/mnt/nfs/media/series` only.

## Quality

Both apps use the **Ultra-HD** profile with upgrades on. Live only
(not in Nix):

| | Movies (Radarr) | Series (Sonarr) |
|---|---|---|
| Cutoff | WEB 2160p | WEB 2160p |
| Allowed above 1080p | WEB 2160p, Bluray-2160p | WEB 2160p, Bluray-2160p |
| Remux | off | off |

Quality definitions (MB/min): 1080p WEB max 15; 4K WEB max 40;
Bluray-2160p max 60. HDTV-2160p (often upscales) stays off.
Anime and documentaries stay off *arr.

## Jellyfin and sidecars

Live only (not in Nix). Radarr and Sonarr Connect (`Emby / Jellyfin`)
point at `127.0.0.1:8096` and update the library on import, upgrade,
rename, and delete. Kodi/XBMC metadata is on: Radarr writes
`movie.nfo` plus poster/fanart; Sonarr writes `tvshow.nfo`, episode
`.nfo`, and artwork. Bazarr writes `.srt` next to Movies/Shows files
and ignores PGS when deciding whether a title already has subs. It
also talks to local Jellyfin so a new subtitle refreshes the library.
Extra files `srt,nfo` stay imported. Anime and documentaries are not
Bazarr roots.

## No VPN

qBittorrent peer traffic leaves this VM's WAN path. There is no
gluetun or WireGuard killswitch
([2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md)).
A home-router inbound forward of the torrenting port is outside this
repo and only affects swarm connectivity.

Listen/DHT is UDP `41666`. libtorrent uses the OS default socket
buffer (212 KiB) unless `net.core.rmem_default` is raised. On this host
that default is 4 MiB so DHT/uTP does not overflow and fire
`TailscaleNodeUDPBufferErrors`. Do not lower it without checking
`ss -uamp` drops (`skmem d…`) on the qBittorrent sockets.

## Memory

`MemoryMax` 1G on Radarr, Sonarr, and qBittorrent; 768M on Prowlarr;
512M on Bazarr; 2G on FlareSolverr (Chromium). Listed in
[memory.md](../memory.md). Check live RSS before raising again.

## Alerting

`ServiceDown` / `ServiceCrashLooping` cover the six units. Blackbox
job `blackbox_http_internal` probes the six tailnet URLs;
`EndpointDown` uses `probe_success`. `TailscaleNodeUDPBufferErrors` is
qBittorrent DHT on this host, not Tailscale itself. Dashboard: Grafana
folder `fleet`, `fleet-media-automation` (includes UDP receive/send
buffer drops). Queue depth and failed grabs need an exporter
(`exportarr`) this flake does not package.

## Out of scope

Lidarr, music. Anime and documentaries stay on
[jellyfin-metadata.md](../runbooks/jellyfin-metadata.md).
