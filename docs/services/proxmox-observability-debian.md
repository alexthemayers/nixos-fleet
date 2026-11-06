# Debian observability guest

**Host:** `proxmox-observability-debian` (VM 111) · **Collection:**
[`fleet.debian_guest`](../../collections/ansible_collections/fleet/debian_guest)

Debian 13 guest for Prometheus, Loki, Grafana, Alertmanager, and ntfy.
It replaces `proxmox-observability` (VM 103). See
[2026-11-04-debian-observability-guest.md](../adr/2026-11-04-debian-observability-guest.md),
[2026-11-04-local-metrics-and-logs.md](../adr/2026-11-04-local-metrics-and-logs.md),
and
[2026-11-06-observability-config-in-ansible.md](../adr/2026-11-06-observability-config-in-ansible.md).

```bash
make deploy-debian-observability
make debian-observability-check
```

## Hardware

| Property | Value |
|----------|-------|
| VMID | 111 |
| CPU | `host`, 4 cores |
| RAM | 8 GiB, balloon off |
| Root | `truenas-storage`, 200 GiB, virtio-scsi |
| NIC | one VF from PCI map `Network-SRIOV`; MAC `82:cc:a5:22:e5:0b` |
| virtio `net0` | `vmbr0`, `link_down=1`. Traffic stays on the X710 VF |
| Boot | `onboot: 1`, `startup: order=2` |
| iGPU | none |
| Tailscale | hostname `proxmox-observability-debian`, port `41645` |

## Updates

Debian and Debian-Security updates apply at 03:30 and the guest restarts at
05:00 when an update asks for it. Third-party repositories and images change
in the monthly window: [updates.md](../runbooks/updates.md).

## What runs

Rootless Podman, host networking, digest-pinned: Prometheus 3.14.0
(62-day TSDB, `MemoryMax` 2.5G), Loki 3.7.7 (filesystem, 62 days,
`MemoryMax` 768M), Grafana 13.1.4 (`MemoryMax` 1G), Alertmanager 0.33.1,
ntfy 2.28.0, blackbox exporter 0.28.0, graphite exporter 0.16.0,
Tailscale exporter 0.7.0. Vector, node exporter, and the systemd exporter
are native. `iperf3 -s` listens on 5201. `alertmanager-ntfy` is the
Python webhook on `127.0.0.1:8095`.

Grafana uses Postgres on `xcloud-postgres`. Garage and Mimir are
decommissioned
([decommission-garage](../adr/2026-11-06-decommission-garage.md)).

Scrape jobs, Alertmanager routes, alert rules, and the Graphite mapping
are committed files in the observability role
(`roles/observability/files/{prometheus,alertmanager,graphite-mapping,rules}.yml`).
Dashboards live under `roles/observability/files/dashboards/` and copy to
`/var/lib/grafana/dashboards/`. Edit those files and apply with
`make deploy-debian-observability`. The observability role restarts
Prometheus, Alertmanager, Loki, ntfy, blackbox, and graphite-exporter when
their files change. Prometheus is restarted, not reloaded: its config and
rules are single-file bind mounts, and `copy` replaces the inode, so
`/-/reload` re-reads the old file.

Prometheus `external_labels.__replica__` is
`proxmox-observability-debian` (renamed from `proxmox-observability` —
series keyed on the old label do not continue under that name).

Vector on this guest (and other debian guests) exposes
`prometheus_exporter` on `:9598`. The Tailscale API exporter listens on
`:9250` with `./tailscale-exporter --listen-address=:9250`; it needs a
valid OAuth client in `tailscale/exporter_env` (invalid token → crash
loop and `TargetDown`).

## Edge

Caddy on `xcloud-caddy` dials this guest for `grafana.alexmayers.co.za`
and `ntfy.alexmayers.co.za`. Vector on the fleet ships to
`proxmox-observability-debian:3100`.

## Secrets and leftover state

`secrets/proxmox-observability-debian` is the live file (alex-only). The
TrueNAS zvol `ssd/garage-iscsi` remains and is not mounted. Do not
`zfs destroy` it until the operator removes the guard in
[decommission-garage](../adr/2026-11-06-decommission-garage.md). That ADR
also lists the unused `loki`, `mimir`, and `garage` secret keys to delete
with `make edit-secrets`.
