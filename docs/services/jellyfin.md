# Jellyfin Service Configuration

Jellyfin is the fleet media server on **`proxmox-applications-1`**. Module:
[`services/jellyfin`](../../services/jellyfin).

## Overview

GPU-accelerated library and streaming. Public URL
`https://jellyfin.alexmayers.co.za` (edge Caddy → `proxmox-lb` → apps-1
`:8096`). Server, encoding, network, branding, library options, and
plugin XML are files under `services/jellyfin/` overlaid at start. Users,
watch state, and plugin DLLs stay on the config NFS share.

## Networking and Ports

- **Listen**: TCP `8096` on `tailscale0` only (`openFirewall = false`).
- **Published URL**: `JELLYFIN_PublishedServerUrl=https://jellyfin.alexmayers.co.za`.
- **KnownProxies**: `jellyfin-render-config.service` resolves `xcloud-caddy`
  and `proxmox-lb` over MagicDNS into `network.xml` at
  `/run/jellyfin/live`, plus `127.0.0.1`. Do not pin Tailscale
  IPv4s in the XML. After a hypervisor reboot those names can lag
  `tailscaled`; `wait-for-host-jellyfin-render-caddy` and
  `-jellyfin-render-lb` gate the render unit. `ServiceDown` /
  `EndpointDown` page if it still fails.

## Storage and Mounts

Jellyfin mounts media, configuration, and cache from TrueNAS:

- **NFS Media Mount**: `truenas-scale:/mnt/hdd/media` → `/mnt/nfs/media`
  with `async` and 1 MiB `rsize`/`wsize`.
- **NFS Config Mount**: `truenas-scale:/mnt/ssd/jellyfin/config` →
  `/mnt/nfs/jellyfin/config` **without** `async`.
- **NFS Cache Mount**: `truenas-scale:/mnt/ssd/jellyfin/cache` →
  `/mnt/nfs/jellyfin/cache` with the same `async` / 1 MiB r/w as media.
  `BindPaths` maps it to `/var/cache/jellyfin`. `CachePath` in
  `system.xml` must stay `/var/cache/jellyfin` so it matches the bind.
- **Connectivity Guard**: mounts require `wait-for-host-jellyfin.service`.
  `jellyfin.service` has `RequiresMountsFor` on media, config, and cache.
- **Systemd Overlay**:
  - NFS configuration binds to `/var/lib/jellyfin`.
  - NFS cache binds to `/var/cache/jellyfin`.
  - NFS media binds to `/media`.
  - Declarative XML is copied to `/run/jellyfin/live` then `BindPaths`
    over the NFS dests (**writable** — Jellyfin rewrites `encoding.xml`
    on start).

NFSv4.2 follows MagicDNS: mount `truenas-scale` by name on `tailscale0`
(MTU 1280), not the LAN IP. Do not pin a Tailscale address. Automount
`x-systemd.idle-timeout=600` can
unmount an idle cache share; the next open remounts it.

The VM root is a 35 G qcow2 on the same TrueNAS SSD pool via Proxmox NFS.
The cache dataset is a dedicated SSD export (~624 GiB). The config
dataset is still owned as uid **3000** (legacy containers user). Do not
`chown` it to the NixOS `jellyfin` uid; the read-only binds do not need
that.

## Secrets

- **`jellyfin/sso_oid_secret`**: Keycloak client secret for the SSO-Auth
  plugin (`OidClientId` `jellyfin`). Injected via
  `sops.templates."jellyfin-sso-auth.xml"`. Edit with
  `make edit-secrets HOST=proxmox-applications-1`. Rotate the Keycloak
  client in lockstep.

## Graphics Hardware Acceleration

- **Drivers**: Intel media, OpenCL compute (HDR→SDR), QSV (`vpl-gpu-rt`).
- **Access**: `jellyfin` is in supplementary groups `render` and `video`.
- **encoding.xml**: `HardwareAccelerationType` `qsv`, devices
  `/dev/dri/renderD128`, hardware encode/decode and VPP tonemap on.

## Declarative configuration

Source files live next to the module. A deploy that changes them restarts
Jellyfin (the unit's `BindReadOnlyPaths` store paths change). Dashboard
edits to these files do not survive a restart.

| Path in repo | Overlay dest |
| --- | --- |
| `config/system.xml` | `/var/lib/jellyfin/config/system.xml` |
| `config/encoding.xml` | `/var/lib/jellyfin/config/encoding.xml` |
| `config/network.xml` | `/run/jellyfin/live/config/network.xml` then bound |
| `config/branding.xml` | `/var/lib/jellyfin/config/branding.xml` |
| `config/database.xml` | `/var/lib/jellyfin/config/database.xml` |
| `config/xbmcmetadata.xml` | `/var/lib/jellyfin/config/xbmcmetadata.xml` |
| `config/logging.json` | `/var/lib/jellyfin/config/logging.json` |
| `plugins/*.xml` | `/var/lib/jellyfin/plugins/configurations/` |
| `libraries/<Name>/` | `/var/lib/jellyfin/root/default/<Name>/` |

Libraries: Anime (`/mnt/nfs/media/anime`), Movies, Documentaries, Music,
Shows (`/mnt/nfs/media/series`). Paths stay the host NFS mountpoints, not
the `/media` bind dest, matching the live library DB.

**Not** in git: `jellyfin.db` / `library.db` (users `alex`,
`alex.mayers`, `callum.mcdonald`, `tim.mayers`; watch progress),
metadata, trickplay, and plugin DLLs (SSO-Auth 4.0.0.4, AniDB 11.0.0.0).
`system.xml` still lists the SSO-Auth plugin repository so the dashboard
can update those DLLs.

SSO branding posts to `/sso/OID/start/keycloak`. Keycloak grants access
([2026-09-04-jellyfin-sso-groups](../adr/2026-09-04-jellyfin-sso-groups.md)):

| Keycloak | Jellyfin |
| --- | --- |
| `jellyfin:read` (default realm role) | All libraries, not admin |
| group `jellyfin admin` | Administrator, all libraries |

Every Keycloak user has `jellyfin:read`. Put a user in `jellyfin admin`
only if they need the dashboard. Do not use realm role `admin` for
Jellyfin. SSO-Auth `RoleClaim` is `roles`. Local password users (`alex`,
`tim.mayers`) are unchanged. CanonicalLinks in `SSO-Auth.xml` map
Keycloak users onto existing Jellyfin GUIDs; do not regenerate those
GUIDs.

- **JSON logging**: Serilog console JSON for Loki (same template as
  before).
- **Stop timeout**: `TimeoutStopSec = "15s"`.
- **Restart**: `on-failure`, `10s`.
- **Transcode throttling**: `EnableThrottling` true, delay 180s, keep
  720s. See
  [2026-08-31-jellyfin-transcode-throttle](../adr/2026-08-31-jellyfin-transcode-throttle.md)
  and
  [2026-09-04-jellyfin-declarative-config](../adr/2026-09-04-jellyfin-declarative-config.md).

Do not set nixpkgs `services.jellyfin.forceEncodingConfig`; its generated
XML is a subset of this host's `encoding.xml`.

## Alerting

`ServiceDown` on `jellyfin-render-config.service` and `EndpointDown` on
`https://jellyfin.alexmayers.co.za/web/`. GPU hangs:
`IntelGPUDriverHang` (`fleet-hardware`).

## I/O benchmark

The Go bench in
[`scripts/jellyfin-io-bench`](../../scripts/jellyfin-io-bench) probes the
NFS cache mount, runs 4K QSV HLS onto that dataset (unthrottled and
`ffmpeg -re`) plus a tmpfs control, and benches **Direct Play** of a 4K
remux clip (default: Oppenheimer UHD). Direct Play drops the page cache,
then:

- fills a 10 s virtual player buffer draining at 128 Mbps (UHD Blu-ray
  max — this file averages ~65 Mbps)
- sequential-reads the same clip uncapped
- demuxes 120 s of the remux with jellyfin-ffmpeg (`-c copy`, then `-re`)

A stall is a buffer underrun or `ffmpeg -re` speed below 0.90 for 1.5 s.
The bench records guest iowait, NFS byte/RPC counters, dest space, and
HTTP availability of `http://127.0.0.1:8096` during transcode load.

It must run **on `proxmox-applications-1`**. Build the `x86_64-linux`
binary on `proxmox-dev` (path flake after rsync), not on the laptop:

```bash
make bench-jellyfin-io
# or: ./scripts/run-jellyfin-io-bench.sh
# DURATION=90s HOST=proxmox-applications-1 ./scripts/run-jellyfin-io-bench.sh probe
# ./scripts/run-jellyfin-io-bench.sh directplay
```

Subcommands: `dns`, `probe` (mount, export, uid write, Jellyfin HTTP,
automount), `transcode` (idle, NFS unthrottled, NFS throttled, tmpfs
throttled), `directplay` (player buffer + sequential + ffmpeg copy),
`all`. JSON goes to `/root/jellyfin-io-bench.json` on the Jellyfin host.
The runner copies the binary to `/root/jellyfin-io-bench.bin`. The flake
attr is `.#packages.x86_64-linux.jellyfin-io-bench`.
