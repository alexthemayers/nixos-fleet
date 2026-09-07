---
status: accepted
date: 2026-09-07
---

# VM root disks stay on TrueNAS NFS

## Context and Problem Statement

[Fleet simplification](../fleet-simplification-plan.md) Phase 1 proposed
moving every guest qcow2 off `truenas-storage` onto a new local NVMe so a
TrueNAS hang would not freeze seven root filesystems. Should the fleet buy
or reclaim that drive and move the disks?

## Decision Drivers

* The B860I has one free M.2 slot; moving disks needs new hardware or a
  live reclaim of the WD Blue SATA pair from VM 100.
* Guest roots are rebuildable from this flake. Application data already
  lives on TrueNAS datasets.
* The operator is not moving drives in this window.

## Considered Options

* Add a 2 TB M.2 as `local-nvme` and `qm disk move` every guest
* Reclaim the two WD Blue SA510s from TrueNAS into a host ZFS mirror
* Keep VM roots on `truenas-scale:/mnt/ssd/proxmox/storage-pool`

## Decision Outcome

Chosen option: "Keep VM roots on
`truenas-scale:/mnt/ssd/proxmox/storage-pool`", because the circular
boot dependency is accepted until hardware is actually installed. Phase 1
in the plan stays a proposal, not a scheduled cutover.

TrueNAS stays at 24 GiB. It still pays for ZFS ARC on the dataset that
backs every guest root.

### Consequences

* Good, because no disk move or NAS shrink happens without a drive in
  hand.
* Bad, because a TrueNAS hang still freezes every NixOS guest root. That
  remains a hub
  ([no internal LB](2026-09-07-no-internal-lb.md)).

## Validation

`qm config` for VMs 101, 102, 103, and 106 still shows
`scsi0: truenas-storage:…`. VM 100 remains `local-lvm`.

## More Information

[fleet-simplification-plan.md](../fleet-simplification-plan.md) Phase 1,
[fleet-simplification-migration.md](../runbooks/fleet-simplification-migration.md).
