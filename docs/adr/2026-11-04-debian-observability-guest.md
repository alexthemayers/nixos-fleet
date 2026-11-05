---
status: accepted
date: 2026-11-04
---

# Observability moves to a Debian guest in fleet.debian_guest

## Context and Problem Statement

`proxmox-observability` (VM 103) is the NixOS guest for metrics, logs,
Grafana, and ntfy. VM 109 and VM 110 already showed how a Debian guest
is installed from `fleet.debian_guest`. How should this guest move
without a second Tailscale node or a second ntfy writer?

## Decision Drivers

* VM 103 stays bootable. Its last generation still has the old stack.
* One Tailscale node. The new guest takes VM 103's node state.
* The public names `grafana.alexmayers.co.za` and
  `ntfy.alexmayers.co.za` stay. Caddy is retargeted after the new
  MagicDNS name resolves.
* Guest roots stay on TrueNAS NFS.

## Considered Options

* Rebuild Debian in place on VM 103
* A new collection, or roles added to `ansible/proxmox.yml`
* VM 111 in `fleet.debian_guest`, same playbook, `--limit` required

## Decision Outcome

Chosen option: "VM 111 in `fleet.debian_guest`, same playbook, `--limit`
required", because the guest lifecycle is already that collection's.

VM 111 is `proxmox-observability-debian`: Debian 13, 4 cores, 8 GiB,
200 GiB qcow2 on `truenas-storage`, one X710 VF, no iGPU. Apply with
`make deploy-debian-observability`. That provisions the guest while
VM 103 is running and does not start Tailscale. The cutover is the
same target with `-e debian_guest_cutover=true`. It shuts VM 103 down,
copies `/var/lib/tailscale` and the local service state, and sets the
node hostname to `proxmox-observability-debian`. The listen port stays
41645. Grafana, Prometheus, Loki, Alertmanager, ntfy, blackbox, the
graphite exporter, and the Tailscale exporter are rootless Podman
units. Tailscale, Vector, node exporter, and the systemd exporter stay
native.

### Consequences

* Good, because rollback is `qm stop 111`, `qm start 103`, and
  `tailscale set --hostname=proxmox-observability`.
* Bad, because metrics, logs, and paging are down from the shutdown
  until Vector and Caddy dial the new name.
* Bad, because the Tailscale node cannot be up on both VMs.

## Validation

`qm status 103` is `stopped` before the cutover apply.
`qm config 111` shows `proxmox-observability-debian`, `memory: 8192`,
and a 200 GiB disk on `truenas-storage`. `tailscale status` reports
the hostname `proxmox-observability-debian`. Grafana
`/api/health` and ntfy `/v1/health` answer through the edge proxy.

## More Information

[proxmox-observability-debian.md](../services/proxmox-observability-debian.md),
[2026-11-04-local-metrics-and-logs.md](2026-11-04-local-metrics-and-logs.md).
