---
status: accepted
date: 2026-09-18
---

# Attic NAR chunks are 8–32 MiB

## Context and Problem Statement

Attic defaulted to 256 KiB average chunks (max 1 MiB). Each chunk is a
Garage PutObject and an LMDB commit with `metadata_fsync`. A unique 64
MiB store path took **66 s (0.97 MiB/s)** on loopback ext4 even though
VM-to-VM iperf is ~6.7–10 Gbit/s. How large should Attic chunks be?

## Decision Drivers

* Fill time is gated on PutObject count, not the tailnet.
* `metadata_fsync = true` stays
  ([garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md)).
* VM roots stay on TrueNAS NFS
  ([nfs-vm-roots](2026-09-07-nfs-vm-roots.md)), so those fsyncs are NFS
  COMMITs.
* The Garage `attic` bucket was emptied 2026-09-18, so mixed chunk
  sizes of old objects are not a concern.

## Considered Options

* Keep 256 KiB / 1 MiB chunks
* 8 MiB average, 32 MiB max, 16 MiB NAR stored whole
* Disable chunking (threshold larger than any NAR)

## Decision Outcome

Chosen option: "8 MiB average, 32 MiB max, 16 MiB NAR stored whole",
because a live bind-mount of that config pushed the same 64 MiB path in
**4.05 s (15.79 MiB/s)** without touching `metadata_fsync`.

That is still two orders below 10 Gbit/s. Closing that gap needs local
fsync for Garage metadata (a local VM disk), which is a hardware move
under nfs-vm-roots, not a chunk-size tweak.

### Consequences

* Good, because fills issue tens of S3 puts per large NAR instead of
  hundreds.
* Bad, because NAR-level dedup is coarser; similar closures share fewer
  chunks.
* Bad, because `attic-nar-proxy` still follows per-chunk 307s; fewer
  chunks also means fewer hops on download.

## Validation

`services/attic.nix` `chunking` is `avg-size = 8388608`,
`max-size = 33554432`, `min-size = 1048576`,
`nar-size-threshold = 16777216`. Repeat `/root/attic-put-bench.sh 64 8`
on `proxmox-dev` through `http://127.0.0.1:8080`.

## Pros and Cons of the Options

### Keep 256 KiB / 1 MiB chunks

* Good, because finer dedup.
* Bad, because 64 MiB fills stay ~1 MiB/s.

### 8 MiB average, 32 MiB max, 16 MiB NAR stored whole

* Good, because measured 16× on a 64 MiB put.
* Bad, because dedup granularity grows with the chunk.

### Disable chunking

* Good, because one PutObject per NAR.
* Bad, because an 800 MiB `linux-firmware` NAR becomes one huge S3
  object and a single timeout loses the lot.

## More Information

[attic.md](../services/attic.md). Garage blocks:
[2026-09-18-garage-blocks-loopback-ext4.md](2026-09-18-garage-blocks-loopback-ext4.md).
NFS COMMIT/LOOKUP alerts: [nfs-congestion.md](../runbooks/nfs-congestion.md).
