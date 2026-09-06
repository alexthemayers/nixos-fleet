# TrueNAS Graphite Exporter Bridge Service Configuration

This document describes the deployment and configuration details of the **TrueNAS Graphite Exporter Bridge** service in
the `nixos-fleet` infrastructure.

## Overview

TrueNAS Scale natively exposes system performance statistics using the Graphite metric format (dot-separated syntax).
Because the central monitoring system is built on Prometheus (which uses label-value dimensions), a translation bridge
is required.

In this fleet, the bridge is deployed on **`proxmox-observability-1`**.

## Networking and Ports

- **Graphite Receiver Port**: Listens on port **`9109`** (accepts Graphite data streams from TrueNAS over TCP/UDP).
- **Prometheus Scrape Port**: Exposes the translated metrics on port **`9108`** (TCP, HTTP).
- **Firewall**: Exposes receiver port `9109` to the Tailscale interface only.

## Metric Mappings (`baseMappings`)

To convert raw Graphite dots strings (e.g. `truenas.nasname.cpu.core.idle`) into structured Prometheus metrics, the
exporter uses a large configuration block of regular expression mappings:

- **Physical Memory**: Matches `truenas.*.system.ram.*` &rarr; `physical_memory{instance="nasname", kind="memorytype"}`.
- **CPU Details**: Matches `truenas.*.system.cpu.*` &rarr; `cpu_total{instance="nasname", kind="idle/user/system"}`.
- **CPU Temperature**: Matches `truenas.*.cputemp.temperatures.*` &rarr;
  `cpu_temperature{instance="nasname", cpu="cpuN"}`.
- **Disk IO Operations**: Matches `truenas.*.disk.*.*` &rarr;
  `disk_io{instance="nasname", disk="sda", op="read/write"}`.
- **ZFS Arcstats**: Matches `truenas.*.truenas_arcstats.*.*` &rarr;
  `truenas_arcstats{instance="nasname", type="subtype"}`.
- **Disk Space and Inodes**: Matches `truenas.*.disk_space.*.used` &rarr;
  `disk_bytes_used{instance="nasname", mountpoint="/mnt/pool"}`.

## Prometheus Scraper Integration

The file appends a custom Prometheus scrape target:

- **Job Name**: `truenas_scale`
- **Target**: Query `proxmox-observability-1:9108` to fetch the processed labels.

TrueNAS Netdata sets `job="truenas"` and `instance="truenas-scale"` on the
mapped series. `job="truenas_scale"` is only the exporter process itself.

## Alerting

Rules live in the `truenas` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix):

| Alert | Catches |
|---|---|
| `TrueNASMetricsStale` | Graphite push stopped (`graphite_last_processed_timestamp_seconds`) |
| `TrueNASExporterDown` | scrape of `:9108` failed |
| `TrueNASZfsPoolNotOnline` | `zfs_pool` one-hot `state` is degraded/faulted/unavail/offline/removed |
| `TrueNASZfsPoolMissingOnline` | a known pool has no `state="online"` series |
| `TrueNASMemoryLow` | `used/(used+free)` above 90% (ARC/cache excluded) |
| `TrueNASHighIOWait` | `cpu_total{kind="iowait"}` above 40% |
| `TrueNASDiskSaturated` | `avg_over_time(disk_utilization[15m])` above 90% |
| `TrueNASPrimaryNicDown` | `enp6s16` operstate is not up |
| `TrueNASClockUnsynced` | `clock_synced=0` |

`zfs_pool` covers `boot_pool`, `hdd`, and `ssd`. Netdata's `disk_space`
charts are the OS mounts (`_root`, `_var_log`), not `/mnt/ssd` or
`/mnt/hdd`, so pool **capacity** is not in this feed and is not alerted.
