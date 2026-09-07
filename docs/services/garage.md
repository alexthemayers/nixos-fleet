# Garage S3 Object Storage Service Configuration

This document describes the deployment and configuration details of the **Garage** S3 service in the `nixos-fleet`
infrastructure.

## Overview

Garage is a lightweight S3-compatible object store. The live node is
**`proxmox-observability`**, `replication_factor = 1`
([garage on obs-1](../adr/2026-09-07-garage-on-obs-1.md)). Cutover from the
retired db pair: [observability-monolith.md](../runbooks/observability-monolith.md).

## Networking and Ports

Garage utilizes three ports, allowed on the Tailscale firewall:

- **`3901`**: RPC port for inter-node communication (gossip mesh).
- **`3902`**: S3 API. `root_domain` is `.s3.alexmayers.co.za` for Host-style
  bucket URLs; there is no public Caddy vhost for that name. Attic, Mimir, and
  Loki use `proxmox-observability:3902`
  ([no internal LB](../adr/2026-09-07-no-internal-lb.md)). Torn LMDB:
  [garage-metadata-resync.md](../runbooks/garage-metadata-resync.md).
- **`3903`**: Admin API / health (`/health`) and Prometheus `/metrics`
  (no `metrics_token`; scrape is unauthenticated).

## Secrets Management

- **`garage/rpc_secret`**: Secret key used for secure node authentication.
- **`garage/admin_token`**: Token used to authorize CLI admin commands.

These are written as `GARAGE_RPC_SECRET_FILE` and `GARAGE_ADMIN_TOKEN_FILE` using SOPS.

## Storage and clustering

- **Replication**: `replication_factor = 1`. One layout node. A reboot of
  obs-1 is an S3 outage until Garage is back.
- **Database engine**: LMDB with `metadata_fsync`
  ([garage-lmdb-migration ADR](../adr/2026-09-05-garage-lmdb-migration.md)).
  There is no peer to table-repair from. Torn metadata is a snapshot restore
  ([garage-metadata-resync.md](../runbooks/garage-metadata-resync.md)).
- **Backing store**: `proxmox-observability` mounts TrueNAS NFS (via
  `fleet.waitForHost` targeting `truenas-scale`):
  `truenas-scale:/mnt/ssd/garage/obs`.

One NFS dataset on the same NAS as everything else: a TrueNAS `ssd` loss
still loses Attic, Loki chunks, and Mimir blocks. RF=1 does not change that.

### Metadata (LMDB)

`/var/lib/garage/meta/db.lmdb/` holds the metadata database.
`metadata_fsync = true` syncs on commit. `lmdb_map_size` is unset: upstream
defaults to 1 TiB on 64-bit, which caps the database size rather than
allocating it. `metadata_auto_snapshot_interval = "6h"` keeps the two most
recent snapshots under `meta/snapshots/`, and rotating them needs up to 4x
the database size in `metadata_dir`.

Garage's own snapshots are the only consistent copy; a filesystem-level copy
taken while Garage runs may be torn. Nodes converted from sqlite keep the old
database as `db.sqlite.migrated-<ts>`, which can be removed once the cluster
is verified healthy. sqlite serialized writers, so a parallel `attic push`
stalled every reader; that is why the engine changed.

`StateDirectory=garage` ID-maps `/var/lib/garage`. On disk the tree is owned by
`nobody:nogroup`; inside the unit that uid is the `garage` service user. `chown
garage:garage` on the host makes those files unmapped (readonly) in the
service. Leave ownership as `nobody:nogroup`.

A node that **cannot start** after a hypervisor hard reset (Garage panic
`resync.rs` / `range end index 8 … slice of length 3`) has no peer. Move
`db.lmdb` aside and restore the latest Garage snapshot
([garage-metadata-resync.md](../runbooks/garage-metadata-resync.md)). Admin
`/health` 200 and an unauthenticated S3 GET 403 mean the daemon is accepting
traffic.

## Layout operations

Roles are not in Nix; they are applied with the Garage CLI on a live node (needs `GARAGE_RPC_SECRET_FILE`):

```
garage layout show
garage layout assign -z <zone> -c <capacity> <node-id>
garage layout remove <node-id>          # stage
garage layout apply --version <n>       # n = current + 1
garage layout skip-dead-nodes --version <n> --allow-missing-data
```

`/health` on `:3903` must return 200 before Loki or Mimir can persist to S3.

## Bootstrapping and key management

A oneshot (`garage-bootstrap`) runs on **`proxmox-observability`** after the daemon is up and a layout has been applied. On cutover, **import** the existing Loki/Mimir/Attic keys before this unit creates new ones:

1. Creates keys under `/var/lib/garage/keys/`.
2. Creates buckets `loki`, `mimir`, `web-assets`, `attic`.
3. Grants those keys read-write on the matching buckets.

## Alerting

Prometheus scrapes `proxmox-observability:3903` (`job=garage`).
The Mimir ruler evaluates the `garage` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). ntfy gets the
page. `TargetDown` already covers a dead scrape. Dashboard: `fleet-garage`.

| Alert | When | What to do |
|-------|------|------------|
| `GarageClusterUnhealthy` | `cluster_healthy=0` for 5m | The layout node is disconnected. Check `garage.service` and the tailnet on obs-1. |
| `GarageClusterUnavailable` | `cluster_available=0` for 1m | Partition quorum is gone. S3 is failing. Same as above; clients use `proxmox-observability:3902`. |
| `GarageMerkleTodoStuck` | merkle TODO > 100 and not falling for 30m | Torn or unreadable metadata. [garage-metadata-resync.md](../runbooks/garage-metadata-resync.md). |
| `GarageBlockResyncErrors` | `block_resync_errored_blocks>0` for 15m | Ghost objects / likely data loss. Do **not** `garage repair blocks`. Same runbook, ghost-objects section. |
| `GarageDiskSpaceLow` / `Critical` | data or metadata volume < 10% / 5% | Data is TrueNAS NFS; metadata is local LMDB. |
| `GarageS3ServerErrorRate` | 5xx > 5% of S3 requests for 5m | NFS or the daemon. Check `cluster_healthy` first. |

Module: [`services/garage.nix`](../../services/garage.nix).
