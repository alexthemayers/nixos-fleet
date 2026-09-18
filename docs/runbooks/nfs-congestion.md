# Runbook: NFS congestion and metadata-bound shares

Use this when `NfsMetadataBound`, `NfsShareWriteSlow`,
`NfsShareCommitSlow`, `NfsShareLookupSlow`, `NfsClientRetransmits`, or
`NfsShareMajorTimeouts` fires, or when a service on NFS is orders of
magnitude slower than iperf to the same host.

**Do not `find` / `du` a hex fanout or millions of small files on raw
NFS from the VM.** That wedges the share (Garage data, 2026-09-18).

**Do not `chown` Garage meta to `garage`.** Unrelated to this page, but
the same host often runs both.

iperf on this mesh is ~6–10 Gbit/s. That does not bound NFS: a WRITE
can sit at 180 ms and a COMMIT at 1 s because the NAS is doing POSIX
metadata or a server-side fsync.

## Confirm

Dashboard: Grafana folder `fleet`, `fleet-nfs`.

```bash
# per host (already scraped)
curl -sS -G http://proxmox-observability:9009/prometheus/api/v1/query \
  --data-urlencode \
  'query=sum by (host,method) (rate(node_nfs_requests_total{proto="4"}[10m])) > 1'

# per export (after collector.mountstats is deployed)
curl -sS -G http://proxmox-observability:9009/prometheus/api/v1/query \
  --data-urlencode \
  'query=node_mountstats_nfs_mountpoint_info'
```

On the VM:

```bash
nfsstat -c
mountstats /mnt/nfs/<share>
```

## What to do

1. **LOOKUP/GETATTR storm, tiny files** (`NfsMetadataBound`,
   `NfsShareLookupSlow`): put a sparse ext4 image on the share and
   loop-mount it (`services.build-cache` or Garage
   [garage-blocks-loopback.md](garage-blocks-loopback.md)). Do not
   keep the application on raw NFS.

2. **Slow WRITE while busy** (`NfsShareWriteSlow`): larger I/O
   (`rsize`/`wsize` 1 MiB, `nconnect=8`, already in
   `config/nfs-mount.nix`), or the same loopback pattern.

3. **Slow COMMIT** (`NfsShareCommitSlow`): the share is fsyncing to
   TrueNAS. Databases and `metadata_fsync` do not belong here. Garage
   already moved that fsync to iSCSI
   ([garage-iscsi.md](garage-iscsi.md)). Remaining NFS COMMIT is other
   shares, or guest-root qcow2
   ([nfs-vm-roots](../adr/2026-09-07-nfs-vm-roots.md)).

4. **Retransmits / major timeouts**: TrueNAS nfsd, ZFS, or the tailnet
   path. Check `TrueNASHighIOWait` / `TrueNASDiskSaturated` on
   `fleet-truenas`.

## Shares in this fleet

Every `fileSystems` NFS client of `truenas-scale` is in scope: GitLab
state image, container-registry, Jellyfin, Immich, Paperless, Luanti,
OpenArena, Actual Budget, and the hypervisor `truenas-storage` pool.
Garage blocks and meta are iSCSI, not this NFS group
([garage-iscsi.md](garage-iscsi.md)). Alerts label `host` and, for
mountstats, `export`.
