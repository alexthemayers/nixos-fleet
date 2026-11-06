---
status: superseded by [2026-09-18-garage-iscsi.md](2026-09-18-garage-iscsi.md)
date: 2026-09-18
---

# Garage blocks sit on a loopback ext4 image on NFS

## Context and Problem Statement

Garage on `proxmox-observability` stores object blocks as a hex fanout of
small files on TrueNAS NFS (`truenas-scale:/mnt/ssd/garage/data`). Attic
chunks average 256 KiB, so a fill is thousands of NFS
open/write/close/rename operations. Measured Attic puts of a fresh 4 MiB
store path through loopback `:8080` completed at **0.10 MiB/s** (41 s)
with `ATTIC_PUSH_JOBS=8`. VM-to-VM iperf is ~6.7 Gbit/s and Garage CPU
sits near idle, so the path is POSIX metadata on NFS, not the tailnet.
How should this node store blocks?

## Decision Drivers

* Attic fill is gated on PutObject completing; 0.10 MiB/s makes large
  NARs time out.
* `metadata_fsync = true` stays
  ([garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md)).
* Object data stays on TrueNAS `ssd`, same as Loki and Mimir.
* `services.build-cache` already mounts a sparse ext4 image on NFS for
  the same class of workload.
* Do not `chown` Garage meta to `garage`. Do not `garage repair blocks`.

## Considered Options

* Keep hex directories on raw NFS
* NFS `nconnect=8` only
* `nconnect=8` plus `compression_level = "none"`
* `nconnect=8` plus a loopback ext4 image on that NFS share
* Local disk on `proxmox-observability`

## Decision Outcome

Chosen option: "`nconnect=8` plus a loopback ext4 image on that NFS
share", because it is the fleet's existing high-I/O NFS pattern and it
turns per-chunk POSIX metadata into block I/O against one image file.

`data_dir` is `/mnt/nfs/garage/data/.blocks-ext4`. The sparse image is
`/mnt/nfs/garage/data/.garage-blocks.img` (virtual size 100G, grow
only). NFS keeps `nconnect=8` and `noatime` for that image file.
`ATTIC_PUSH_JOBS` stays 8. Garage compression stays at upstream default
(zstd).

The live cluster was emptied onto this image on 2026-09-18 rather than
copied. Attic Postgres object rows were truncated the same day
([attic-ghost-narinfos.md](../runbooks/attic-ghost-narinfos.md)).
Historical Loki chunks and Mimir blocks in Garage are gone. Runbook:
[garage-blocks-loopback.md](../runbooks/garage-blocks-loopback.md).

### Consequences

* Good, because Attic puts no longer pay NFS LOOKUP/rename per 256 KiB
  chunk.
* Good, because the image is one NFS file, so `nconnect` still helps the
  remaining remote I/O.
* Bad, because the 100G ext4 is what `garage_local_disk_*` reports;
  growing it is an operator step, not a NAS quota change.
* Bad, because a first-boot `e2fsck` of the image delays Garage until it
  finishes.
* Bad, because emptying S3 throws away Attic NARs, Loki chunks, and
  Mimir blocks already in Garage. Refill Attic; accept the observability
  gap.
* Bad, because unused NFS hex directories remain until deleted from
  TrueNAS. Do not `find`/`du` them from the VM.

## Validation

Attic put of a unique urandom store path, `ATTIC_PUSH_JOBS=8`, endpoint
`http://127.0.0.1:8080` on `proxmox-dev`:

| Step | Size | Wall | Throughput |
|------|------|------|------------|
| Raw NFS (baseline) | 4 MiB | 41.16 s | 0.10 MiB/s |
| Same, `ATTIC_PUSH_JOBS=2` | 4 MiB | 38.58 s | 0.10 MiB/s |
| NFS `nconnect=8` | 4 MiB | 15.35 s | 0.26 MiB/s |
| `nconnect=8` + `compression_level=none` | 4 MiB | 17.87 s | 0.22 MiB/s |
| Loopback ext4 (cold / two warms) | 4 MiB | 16.20 / 8.16 / 11.02 s | 0.25 / 0.49 / 0.36 MiB/s |
| Loopback ext4 | 64 MiB | 66.20 s | 0.97 MiB/s |
| Loopback ext4 + 8–32 MiB Attic chunks | 64 MiB | 4.05 s | 15.79 MiB/s |

Jobs and disabling compression do not help. A 64 MiB put on raw NFS
timed out; the same put on loopback finished. `/health` on `:3903`
returns 200 and an unauthenticated GET on `:3902` returns 403.
`data_dir` is the loop mount. Module: `services/garage.nix` (deleted in
[2026-11-06-observability-config-in-ansible.md](2026-11-06-observability-config-in-ansible.md)).

## Pros and Cons of the Options

### Keep hex directories on raw NFS

* Good, because no migration.
* Bad, because fills stay at ~0.10 MiB/s.

### NFS `nconnect=8` only

* Good, because it is a mount-option change and measured ~2.7×.
* Bad, because each PutObject is still a burst of NFS metadata.

### `nconnect=8` plus `compression_level = "none"`

* Good, because it skips zstd on the daemon.
* Bad, because urandom NARs measured slower than nconnect alone.

### `nconnect=8` plus a loopback ext4 image on that NFS share

* Good, because it matches `services.build-cache`.
* Good, because Garage sees local POSIX.
* Bad, because capacity is the image size, and a populate-by-copy is
  slow (this cluster wiped instead).

### Local disk on `proxmox-observability`

* Good, because it would be the fastest.
* Bad, because it splits object data off the TrueNAS `ssd` dataset that
  already holds Loki and Mimir.

## More Information

[garage.md](../services/garage.md). Placement:
[2026-09-07-garage-on-obs-1.md](2026-09-07-garage-on-obs-1.md).
Build-cache pattern: [custom-options.md](../custom-options.md).
