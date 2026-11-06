---
status: accepted
date: 2026-11-04
---

# Prometheus and Loki keep 62 days on local disk

## Context and Problem Statement

VM 103 stored metrics in Mimir and logs in Loki, both backed by Garage
on a TrueNAS iSCSI zvol. The Debian guest replaces that VM. Should
Garage and Mimir move with it?

## Decision Drivers

* Garage's only remaining clients are Mimir and Loki. Attic is gone.
* The zvol is the only copy of the old blocks and chunks.
* Prometheus on VM 103 is an agent. It has no local history to import.
* One disk on the new guest has to hold the new retention.

## Considered Options

* Move Garage and Mimir onto the Debian guest
* Import the Garage buckets onto local disk
* Drop Garage and Mimir. Prometheus and Loki each keep 62 days on the
  guest disk. Leave the zvol in place.

## Decision Outcome

Chosen option: "Drop Garage and Mimir. Prometheus and Loki each keep
62 days on the guest disk. Leave the zvol in place."

Prometheus is a server with `--storage.tsdb.retention.time=62d` and
`MemoryMax` 2.5G. It evaluates the rules in
`collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml`, minus the `iscsi`, `garage`, `mimir`, and
`mimir-ruler` groups. Loki uses a filesystem store and
`retention_period` 1488h. Grafana's Prometheus datasource is
`127.0.0.1:9090`. The guest does not log into
`192.168.3.9:3260`. `ssd/garage-iscsi` and the TrueNAS target stay.
VM 103's last generation can still mount them.

### Consequences

* Good, because a second initiator cannot corrupt the zvol.
* Bad, because Grafana has no samples or lines from before the cutover.
* Bad, because destroying the zvol later deletes that history.

## Validation

Prometheus is not in agent mode. A rule group is loaded. Loki answers
a push. `findmnt` on the guest has no `/mnt/iscsi/garage`. Nothing
listens on `:9009` or `:3902`.

## More Information

[proxmox-observability-debian.md](../services/proxmox-observability-debian.md),
[2026-11-04-debian-observability-guest.md](2026-11-04-debian-observability-guest.md).
