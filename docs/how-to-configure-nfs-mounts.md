# How-To: Configure NFS Mounts & Storage Availability

In a distributed homelab, mounting NAS directories over a Tailscale mesh network introduces boot-time race conditions.
If NixOS attempts to mount NFS volumes before Tailscale has established a connection to the NAS, the mount will fail,
potentially dropping the system into emergency mode.

This guide explains how to use the `fleet.waitForHost` module to prevent these issues, and when to utilize the
`build-cache` loopback pattern.

## Using `fleet.waitForHost`

The `fleet.waitForHost` custom option automatically generates a systemd `oneshot` service that pings the target NAS
until it is reachable over the network.

### Implementation

1. **Enable the guard** in your service module (e.g., `services/myservice.nix`):
   ```nix
   fleet.waitForHost.myservice.host = "truenas-scale";
   ```
2. **Apply the guard to your file system mount**:
   You must instruct systemd to delay the mount until the wait-for-host service completes. Add the `x-systemd.requires`
   and `x-systemd.after` options:
   ```nix
   fileSystems."/mnt/nfs/myservice" = {
     device = "truenas-scale:/mnt/ssd/myservice";
     fsType = "nfs";
     options = [
       "nfsvers=4.2"
       "_netdev" # Indicates this requires network access
       "nconnect=8"
       "noatime"
       "x-systemd.automount"
       "x-systemd.idle-timeout=600"
       "x-systemd.requires=wait-for-host-myservice.service"
       "x-systemd.after=wait-for-host-myservice.service"
     ];
   };
   ```

### Tradeoffs

- **Pros**: Prevents boot hangs and emergency mode drops. Automatically handles the timing intricacies of Tailscale's
  userspace initialization.
- **Cons**: Increases overall boot time of the host by a few seconds while waiting for network discovery.

---

## High-I/O & Locking: The Loopback Block Device Pattern

Raw NFS is unsuitable for applications that require high I/O, POSIX strict locking, or high-concurrency (e.g., Container
Registries, GitLab, Nix builders). Raw NFS mounts can suffer from lock contention and permission mapping issues.

To solve this, we use the `build-cache.nix` pattern: mounting an NFS directory, creating a massive sparse image file,
and mounting it back to the host via a loop device. Garage blocks on
`proxmox-observability` follow the same layout in
[`services/garage.nix`](../services/garage.nix)
([garage-blocks-loopback.md](runbooks/garage-blocks-loopback.md)).

### Implementation Concept

(See `config/build-cache.nix` for the full implementation details).

1. Mount the underlying NFS directory (e.g., `/mnt/nfs/build-cache-backing`).
2. Utilize a `preStart` script in a systemd service to create an `ext4` sparse file:
   ```bash
   truncate -s 100G /mnt/nfs/build-cache-backing/cache.img
   mkfs.ext4 -F /mnt/nfs/build-cache-backing/cache.img
   ```
3. Mount the file via `loop`:
   ```bash
   mount -o loop /mnt/nfs/build-cache-backing/cache.img /var/cache/build
   ```

### Tradeoffs

- **Pros**: Bypasses NFS locking issues. Applications see a native local `ext4` block device, resulting in significantly
  faster operations for tools like `git` and SQLite.
- **Cons**: You lose the ability to easily browse the files directly on the NAS file manager (it's just a `.img` file).
  Size expansion requires unmounting and running `resize2fs`.

---

## Alerting

Every fleet NFS client (and the hypervisor `truenas-storage` pool) is in
the Mimir `nfs` group
([`services/mimir-rules.nix`](../services/mimir-rules.nix)). Dashboard:
`fleet-nfs`. Runbook: [nfs-congestion.md](runbooks/nfs-congestion.md).

`node_nfs_*` is per host and already scraped. `node_mountstats_*` is per
`export` after `collector.mountstats` (needs a node_exporter restart on
each NFS client).

| Alert | When | Meaning |
|-------|------|---------|
| `NfsClientRetransmits` | >5 retransmits in 15m | NAS dropping RPCs |
| `NfsMetadataBound` | LOOKUP/GETATTR >3× READ+WRITE and >30/s | Tiny-file / POSIX metadata workload |
| `NfsShareWriteSlow` | WRITE p̄ >250ms at >5/s | Share cannot do small writes |
| `NfsShareCommitSlow` | COMMIT p̄ >1s at >0.5/s | fsync-to-NAS; wrong protocol for DBs |
| `NfsShareLookupSlow` | LOOKUP >20/s and >100ms | Directory walk on raw NFS |
| `NfsShareMajorTimeouts` | any major timeout | Server not answering |

`nconnect=8` and `noatime` are in `config/nfs-mount.nix` for every
consumer of that helper. GitLab's mount sets the same by hand because
it must not idle-unmount.
