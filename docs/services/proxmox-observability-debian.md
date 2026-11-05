# Debian observability guest

**Host:** `proxmox-observability-debian` (VM 111) · **Collection:**
[`fleet.debian_guest`](../../collections/ansible_collections/fleet/debian_guest)

Debian 13 guest for Prometheus, Loki, Grafana, Alertmanager, and ntfy.
It replaces `proxmox-observability` (VM 103). See
[2026-11-04-debian-observability-guest.md](../adr/2026-11-04-debian-observability-guest.md)
and
[2026-11-04-local-metrics-and-logs.md](../adr/2026-11-04-local-metrics-and-logs.md).

Provisioning leaves VM 103 running and does not start Tailscale:

```bash
make deploy-debian-observability
```

The cutover shuts VM 103 down, copies its Tailscale node and local
state, and starts the stack:

```bash
make deploy-debian-observability ANSIBLE_ARGS="-e debian_guest_cutover=true"
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
| Tailscale | same node as VM 103, hostname `proxmox-observability-debian`, port `41645` |

Do not run `tailscaled` on VM 111 and VM 103 at the same time.

## Updates

Debian and Debian-Security updates apply at 03:30 and the guest restarts at
05:00 when an update asks for it. Third-party repositories and images change
in the monthly window: [updates.md](../runbooks/updates.md).

## What runs

Rootless Podman, host networking, digest-pinned to the versions VM 103
ran: Prometheus 3.14.0 (62-day TSDB, `MemoryMax` 2.5G), Loki 3.7.7
(filesystem, 62 days, `MemoryMax` 768M), Grafana 13.1.4 (`MemoryMax`
1G), Alertmanager 0.33.1, ntfy 2.28.0, blackbox exporter 0.28.0,
graphite exporter 0.16.0, Tailscale exporter 0.7.0. Vector, node
exporter, and the systemd exporter are native. `iperf3 -s` listens on
5201. `alertmanager-ntfy` is the Python webhook on `127.0.0.1:8095`.

Grafana uses Postgres on `xcloud-postgres`. ntfy's `user.db` is copied
from VM 103. Prometheus and Loki start empty. The Garage zvol is not
mounted.

Scrape jobs, Alertmanager routes, alert rules, and the Graphite mapping
are rendered from the NixOS modules at apply time
(`render-config.py`). That evaluates `nixosConfigurations.proxmox-observability`
in `flake.nix`, which is render-only: VM 103 is destroyed, and it has no deploy
node and is not in `fleet.inventory.nixosHosts`. Do not delete it. The role's
stack tasks run behind `debian_guest_cutover`; to ship a rules change without
that, render with `python3 roles/observability/files/render-config.py . /tmp/obs-new`,
copy the files to `/etc/observability/`, and `curl -XPOST localhost:9090/-/reload`.
Dashboards copy to `/var/lib/grafana/dashboards/`.

Vector on this guest (and other debian guests) exposes
`prometheus_exporter` on `:9598`. The Tailscale API exporter listens on
`:9250` with `./tailscale-exporter --listen-address=:9250`; it needs a
valid OAuth client in `tailscale/exporter_env` (invalid token → crash
loop and `TargetDown`).

## Edge

Caddy on `xcloud-caddy` dials this guest for `grafana.alexmayers.co.za`
and `ntfy.alexmayers.co.za`. Vector on the fleet ships to
`proxmox-observability-debian:3100`.

## Rollback

VM 103 and its qcow2 disk were destroyed on 2026-11-04. There is no
NixOS guest to start. `secrets/proxmox-observability` remains, and the
TrueNAS zvol `ssd/garage-iscsi` remains. Do not `zfs destroy` it.
