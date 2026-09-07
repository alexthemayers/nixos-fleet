---
status: accepted
date: 2026-09-07
---

# Garage is a single node on proxmox-observability

## Context and Problem Statement

Garage ran `replication_factor = 2` on `proxmox-db-1` and `proxmox-db-2`.
Both data directories were datasets on the same TrueNAS `ssd` mirror. Zone
redundancy was `maximum`, so one VM reboot made S3 read-only. Should the
fleet keep that pair, retire S3 entirely, or run one Garage node?

## Decision Drivers

* RF=2 on one physical mirror buys no durability against NAS or hypervisor
  loss.
* Loki, Mimir, and Attic already talk to Garage at `proxmox-lb:3902`
  ([Garage S3 via LB](2026-08-30-garage-s3-lb.md)).
* Retiring Garage for local filesystem backends is more data movement than
  collapsing the pair
  ([fleet simplification plan](../fleet-simplification-plan.md) Phase 3).

## Considered Options

* Keep db-1 / db-2 at RF=2
* New RF=1 cluster on `proxmox-observability`; retire the db VMs
* Filesystem backends on obs-1 and `proxmox-dev`; delete Garage

## Decision Outcome

Chosen option: "New RF=1 cluster on `proxmox-observability`", because it
removes two VMs and the false quorum without changing Attic, Loki, or Mimir
storage type. S3 clients now use `proxmox-observability:3902`
([no internal LB](2026-09-07-no-internal-lb.md)).

`replication_factor` cannot change on a live cluster. The cutover is a new
layout on obs-1, import of the existing S3 keys, then Caddy pointed at
obs-1. Runbook:
[observability-monolith.md](../runbooks/observability-monolith.md).

`proxmox-db-1` and `proxmox-db-2` are removed from inventory (VMs 107
and 108 destroyed 2026-09-07). The new
cluster stores blocks on TrueNAS NFS
(`truenas-scale:/mnt/ssd/garage/obs`), not the live db-1 dataset. Metadata
is local LMDB on `proxmox-observability`.

### Consequences

* Good, because a db VM reboot is no longer a write outage.
* Good, because merkle split-brain between two sqlite/LMDB copies cannot
  happen.
* Bad, because Garage is now a fifth load on the observability VM. Size
  obs-1 at 8 GiB before the switch.
* Bad, because RF=1 plus one NFS dataset is one copy of object data. A
  TrueNAS `ssd` loss still loses Attic, Loki chunks, and Mimir blocks.
* Landmines that remain: do not `chown` meta to `garage`; do not
  `garage repair blocks`; S3 clients use `proxmox-observability:3902`
  (`infrastructure.mdc`).

## Validation

`job=garage` scrapes `proxmox-observability:3903` only. Clients call
`:3902` on that host. `garage status` shows one layout node and
`replication_factor = 1`.

## More Information

[garage.md](../services/garage.md). LMDB:
[2026-09-05-garage-lmdb-migration.md](2026-09-05-garage-lmdb-migration.md).
S3 clients: [2026-09-07-no-internal-lb.md](2026-09-07-no-internal-lb.md).
