# Jellyfin Service Configuration

This document describes the deployment and configuration details of the **Jellyfin** service in the `nixos-fleet`
infrastructure.

## Overview

Jellyfin is a self-hosted media server that organizes and streams movie, show, and music assets. It is deployed on the
general applications node, **`proxmox-applications-1`**, which is specifically utilized for workloads requiring GPU
hardware acceleration.

## Networking and Ports

- **Ports**: Exposes standard media ports with firewall rules enabled.
- **Public Domain**: `https://jellyfin.alexmayers.co.za` (reverse proxied via Caddy).

## Storage and Mounts

Jellyfin mounts its media assets, configuration, and cache from TrueNAS:

- **NFS Media Mount**: `truenas-scale:/mnt/hdd/media` is mounted to `/mnt/nfs/media` with `async` and 1 MiB
  `rsize`/`wsize` for sequential read throughput.
- **NFS Config Mount**: `truenas-scale:/mnt/ssd/jellyfin/config` is mounted to `/mnt/nfs/jellyfin/config` **without**
  `async` so library metadata and `system.xml` writes are not buffered unsafely on a crash.
- **NFS Cache Mount**: `truenas-scale:/mnt/ssd/jellyfin/cache` is mounted to `/mnt/nfs/jellyfin/cache` with the same
  `async` / 1 MiB r/w options as media. Systemd `BindPaths` maps it to `/var/cache/jellyfin` (NixOS default
  `cacheDir`). `CachePath` in `system.xml` must stay `/var/cache/jellyfin` so it matches the bind, not the host
  mountpoint — Jellyfin honours `CachePath` over `--cachedir` and will refuse to start if that path is missing inside
  the unit.
- **Connectivity Guard**: Mounts use common options referencing oneshot wait service `wait-for-host-jellyfin.service`
  to prevent boot degradation. `jellyfin.service` has `RequiresMountsFor` on media, config, and cache, so a failed
  cache automount keeps Jellyfin down.
- **Systemd Overlay**: Systemd sandboxing restricts write permissions to the mounts using `BindPaths`:
    - NFS configuration binds to `/var/lib/jellyfin`.
    - NFS cache binds to `/var/cache/jellyfin`.
    - NFS media binds to `/media`.

NFSv4.2 follows MagicDNS: `truenas-scale` is Tailscale `100.96.189.123` (MTU 1280), not the LAN IP. Automount
`x-systemd.idle-timeout=600` can unmount an idle cache share; the next open remounts it.

The VM root is a 35 G qcow2 on the same TrueNAS SSD pool via Proxmox NFS. Putting cache on that disk is still NAS
I/O, with less space. The original cache dataset is a dedicated SSD export (~624 GiB).

## Graphics Hardware Acceleration

Jellyfin transcodes files on-the-fly using graphics adapters:

- **Drivers**: Configures hardware graphics with Intel media drivers, OpenCL compute runtime (critical for HDR to SDR
  tone mapping), and QuickSync Video (QSV) runtime for Arrow Lake architecture:
  ```nix
  extraPackages = with pkgs; [
    intel-media-driver
    intel-compute-runtime
    vpl-gpu-rt
  ];
  ```
- **Access**: Adds the `jellyfin` system user to the supplementary groups `render` and `video`.

## Key Configurations

- **JSON Logging Integration**: To allow Loki to ingest and parse Jellyfin logs, a custom Serilog configuration file (
  `logging.json`) is written to `/var/lib/jellyfin/config/logging.json` inside the `preStart` script, configuring
  console output to write logs in raw JSON format.
- **Stop Timeout Override**: Jellyfin can hang on service termination if threads fail to exit. To resolve this, the
  systemd service defines a stop timeout overlay:
  ```nix
  serviceConfig.TimeoutStopSec = "15s";
  ```
  This is marked in the code as "the silver bullet for the shutdown hang".
- **Restart Settings**: Configures service restart on-failure with a `10s` delay.
- **Transcode throttling**: `encoding.xml` has `EnableThrottling` on (`ThrottleDelaySeconds` 180,
  `SegmentKeepSeconds` 720). `preStart` rewrites a `false` value back to `true` so a dashboard uncheck
  does not survive restart. Unthrottled 4K QSV HLS runs at ~15× realtime; throttling is what keeps guest
  iowait at idle on the SSD NFS cache. See
  [2026-08-31-jellyfin-transcode-throttle](../adr/2026-08-31-jellyfin-transcode-throttle.md).

## I/O benchmark

The Go bench in [`scripts/jellyfin-io-bench`](../../scripts/jellyfin-io-bench) probes the NFS cache mount and
runs 4K QSV HLS onto that dataset (unthrottled and `ffmpeg -re`) plus a tmpfs control. It records guest iowait,
NFS byte/RPC counters, dest space, and HTTP availability of `http://127.0.0.1:8096` during the load.

It must run **on `proxmox-applications-1`**. Build the `x86_64-linux` binary on
`proxmox-dev` (path flake after rsync), not on the laptop:

```bash
make bench-jellyfin-io
# or: ./scripts/run-jellyfin-io-bench.sh
# DURATION=90s HOST=proxmox-applications-1 ./scripts/run-jellyfin-io-bench.sh probe
```

Subcommands: `dns`, `probe` (mount, export, uid write, Jellyfin HTTP, automount), `transcode` (idle, NFS
unthrottled, NFS throttled, tmpfs throttled), `all`. JSON goes to `/root/jellyfin-io-bench.json` on the Jellyfin
host. The runner copies the binary to `/root/jellyfin-io-bench.bin`. The flake attr is
`.#packages.x86_64-linux.jellyfin-io-bench`.
