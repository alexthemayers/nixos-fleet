# Garage S3 Object Storage Service Configuration

This document describes the deployment and configuration details of the **Garage** S3 service in the `nixos-fleet`
infrastructure.

## Overview

Garage is a lightweight S3-compatible object store. The Debian
observability guest does not run it. The zvol `ssd/garage-iscsi` is
still the copy of the old Mimir blocks and Loki chunks. VM 103 was
destroyed on 2026-11-04, so nothing currently mounts it.
`replication_factor = 1`
([garage on obs-1](../adr/2026-09-07-garage-on-obs-1.md)). Historical
move from the retired db pair:
[observability-monolith.md](../runbooks/observability-monolith.md).

## Networking and Ports

Garage utilizes three ports, allowed on the Tailscale firewall:

- **`3901`**: RPC port for inter-node communication (gossip mesh).
- **`3902`**: S3 API. `root_domain` is `.s3.alexmayers.co.za` for Host-style
  bucket URLs; there is no public Caddy vhost for that name. Mimir and
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
  `proxmox-observability` is an S3 outage until Garage is back.
- **Database engine**: LMDB with `metadata_fsync`
  ([garage-lmdb-migration ADR](../adr/2026-09-05-garage-lmdb-migration.md)).
  There is no peer to table-repair from. Torn metadata is a snapshot restore
  ([garage-metadata-resync.md](../runbooks/garage-metadata-resync.md)).
- **Backing store**: TrueNAS iSCSI zvol `ssd/garage-iscsi` on the LAN
  VF (`192.168.3.9:3260`), not MagicDNS
  ([garage-iscsi](../adr/2026-09-18-garage-iscsi.md)).
  `data_dir` is `/mnt/iscsi/garage/data`. `metadata_dir` is
  `/mnt/iscsi/garage/meta`. The leftover NFS share is only a migrate
  source until `mountNfs = false`.

One zvol on the same NAS as everything else: a TrueNAS `ssd` loss
still loses Loki chunks and Mimir blocks. RF=1 does not change that.

### Blocks and metadata (iSCSI ext4)

NFS to this VM is Tailscale MTU 1280. Object uploads on the old NFS loop
image peaked at 15.79 MiB/s because every chunk still fsynced LMDB on
the NFS VM root. The LUN is block I/O on `enp6s16`:

- Portal: `192.168.3.9:3260`. Target:
  `iqn.2005-10.org.freenas.ctl:garage`.
- Initiator: `iqn.2026-09.za.co.alexmayers:proxmox-observability`.
- Mount: `/mnt/iscsi/garage` (`noatime`). Init: `iscsi-login-garage`,
  `garage-iscsi-mkfs`, `garage-iscsi-migrate`.
- `chown garage:garage` is required on that mount. Never chown
  `/var/lib/garage`.

`GarageDiskSpaceLow` / `Critical` read `garage_local_disk_*` of this
100G ext4. Grow the zvol, then `resize2fs`
([garage-iscsi.md](../runbooks/garage-iscsi.md)).

NFS congestion pages still cover other shares:
[nfs-congestion.md](../runbooks/nfs-congestion.md).

### Metadata (LMDB)

`/mnt/iscsi/garage/meta/db.lmdb/` holds the metadata database.
`metadata_fsync = true` syncs on commit. `lmdb_map_size` is unset: upstream
defaults to 1 TiB on 64-bit, which caps the database size rather than
allocating it. `metadata_auto_snapshot_interval = "6h"` keeps the two most
recent snapshots under `meta/snapshots/`, and rotating them needs up to 4x
the database size in `metadata_dir`.

Garage's own snapshots are the only consistent copy; a filesystem-level copy
taken while Garage runs may be torn. Nodes converted from sqlite keep the old
database as `db.sqlite.migrated-<ts>`, which can be removed once the cluster
is verified healthy. sqlite serialized writers, so a parallel PutObject
burst stalled every reader; that is why the engine changed.

A leftover copy may still sit under `/var/lib/garage/meta` on the VM
root. That tree is idmapped (`nobody:nogroup`). Do not chown it to
`garage`. The daemon (when it ran) did not open it.

`StateDirectory=garage` still ID-maps `/var/lib/garage` for key files
under `/var/lib/garage/keys/`.

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

A oneshot (`garage-bootstrap`) used to run on **`proxmox-observability`**
after the daemon was up and a layout applied. When bringing Garage back,
**import** existing Loki and Mimir keys before that unit creates new ones:

1. Creates keys under `/var/lib/garage/keys/`.
2. Creates buckets `loki`, `mimir`, `web-assets`.
3. Grants those keys read-write on the matching buckets.

The `attic` bucket is no longer bootstrapped. Delete it by hand after
atticd is stopped
([2026-11-03-decommission-attic.md](../adr/2026-11-03-decommission-attic.md)).

## Alerting

Prometheus scrapes `proxmox-observability:3903` (`job=garage`).
The Mimir ruler evaluates the `garage` group in
[`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml). ntfy gets the
page. `TargetDown` already covers a dead scrape. Dashboard: `fleet-garage`.

| Alert | When | What to do |
|-------|------|------------|
| `GarageClusterUnhealthy` | `cluster_healthy=0` for 5m | The layout node is disconnected. Check `garage.service` and the tailnet on `proxmox-observability`. |
| `GarageClusterUnavailable` | `cluster_available=0` for 1m | Partition quorum is gone. S3 is failing. Same as above; clients use `proxmox-observability:3902`. |
| `GarageMerkleTodoStuck` | merkle TODO > 100 and not falling for 30m | Torn or unreadable metadata. [garage-metadata-resync.md](../runbooks/garage-metadata-resync.md). |
| `GarageBlockResyncErrors` | `block_resync_errored_blocks>0` for 15m | Ghost objects / likely data loss. Do **not** `garage repair blocks`. Same runbook, ghost-objects section. |
| `GarageDiskSpaceLow` / `Critical` | data or metadata volume < 10% / 5% | Data and meta are the 100G iSCSI ext4. Grow the zvol. |
| `GarageS3ServerErrorRate` | 5xx > 5% of S3 requests for 5m | iSCSI or the daemon. Check `cluster_healthy` first. |
| `IscsiGarageMountMissing` | `/mnt/iscsi/garage` absent while node_exporter is up | Session or mkfs. [garage-iscsi.md](../runbooks/garage-iscsi.md). |
| `IscsiGarageLoginFailed` | `iscsi-login-garage.service` failed | Portal `192.168.3.9:3260` or initiator IQN. Same runbook. |

Dashboard: `fleet-garage`. NFS client congestion for remaining TrueNAS
mounts is the `nfs` group (`fleet-nfs`).

The Nix module `services/garage.nix` was deleted with the Debian cutover
([2026-11-06-observability-config-in-ansible.md](../adr/2026-11-06-observability-config-in-ansible.md)).
Garage stays offline; the TrueNAS zvol freeze remains
([infrastructure.mdc](../../.cursor/rules/infrastructure.mdc)).
