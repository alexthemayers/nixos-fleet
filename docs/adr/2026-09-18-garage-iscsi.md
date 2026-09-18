---
status: accepted
date: 2026-09-18
---

# Garage data and metadata sit on a TrueNAS iSCSI LUN

## Context and Problem Statement

Attic PutObject through Garage on `proxmox-observability` stayed two
orders below the 10 Gbit/s VF even after `nconnect=8`, a loopback ext4
image on NFS, and 8–32 MiB NAR chunks (15.79 MiB/s for a 64 MiB put).
NFS to `truenas-scale` is MagicDNS (`100.96.189.123`, MTU 1280). LMDB
`metadata_fsync` still committed on the NFS-backed VM root. Should
Garage keep using that NFS path?

## Decision Drivers

* iperf on this mesh is ~6.7–10 Gbit/s. NFS COMMIT on the share was ~1.2 s.
* `metadata_fsync = true` stays
  ([garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md)).
* VM roots stay on TrueNAS NFS
  ([nfs-vm-roots](2026-09-07-nfs-vm-roots.md)); only Garage's dataset
  moves.
* Object data stays on the TrueNAS `ssd` pool.
* Do not `chown` `/var/lib/garage` (idmapped). Do not
  `garage repair blocks`.

## Considered Options

* Keep loopback ext4 on NFS
* iSCSI zvol for `data_dir` and `metadata_dir` over the LAN VF
* Local disk on `proxmox-observability`

## Decision Outcome

Chosen option: "iSCSI zvol for `data_dir` and `metadata_dir` over the
LAN VF", because a block LUN on `192.168.3.9:3260` is POSIX fsync
without NFSv4 COMMIT or Tailscale encapsulation.

* Zvol: `ssd/garage-iscsi` (100G, thick, LZ4, 16K volblocksize)
* Target: `iqn.2005-10.org.freenas.ctl:garage`, LUN 0
* Initiator: `iqn.2026-09.za.co.alexmayers:proxmox-observability`
* Portal: TrueNAS `enp6s16` `192.168.3.9:3260` (not MagicDNS)
* Mount: `/mnt/iscsi/garage` (`data/` + `meta/`)

Supersedes
[garage-blocks-loopback-ext4](2026-09-18-garage-blocks-loopback-ext4.md)
for the live `data_dir`. The NFS loop image remains only as a migrate
source until `mountNfs = false`.

### Consequences

* Good, because LMDB fsync and block writes hit a zvol, not NFS.
* Good, because the 10 Gbit VF is used; NFS stayed on Tailscale MTU 1280.
* Bad, because iSCSI is another TrueNAS SPOF path (portal 3260).
* Bad, because capacity is the 100G zvol, same as the old image.
* Bad, because the initiator IQN is a freeze: changing it needs the
  TrueNAS ACL.

## Validation

Module: [`services/garage.nix`](../../services/garage.nix). Runbook:
[garage-iscsi.md](../runbooks/garage-iscsi.md). Alerts:
`IscsiGarageMountMissing`, `IscsiGarageLoginFailed`. After switch:
`/health` 200, unauthenticated `:3902` 403, `findmnt /mnt/iscsi/garage`
is the LUN, `data_dir` / `metadata_dir` under that mount.

## Pros and Cons of the Options

### Keep loopback ext4 on NFS

* Good, because it is already live.
* Bad, because NFS is still MagicDNS, and meta fsync is still the VM root.

### iSCSI zvol for `data_dir` and `metadata_dir` over the LAN VF

* Good, because it is block I/O on the same `ssd` pool, on the LAN.
* Bad, because TrueNAS iSCSI is not in this flake; the target is QGA/`midclt`.

### Local disk on `proxmox-observability`

* Good, because it would be the fastest.
* Bad, because it splits object data off TrueNAS `ssd` and needs hardware
  the nfs-vm-roots freeze already deferred.

## More Information

[garage.md](../services/garage.md). Placement:
[2026-09-07-garage-on-obs-1.md](2026-09-07-garage-on-obs-1.md).
