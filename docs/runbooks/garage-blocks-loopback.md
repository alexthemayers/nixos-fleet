# Runbook: Garage blocks on loopback ext4

Use this on **`proxmox-observability`** when creating the block image,
pointing `data_dir` at the loop mount, growing the image, or wiping
S3 and starting empty.

Nix creates and fscks the image. It does **not** copy or delete
blocks.

**Do not `chown /var/lib/garage` to `garage`.** Meta is idmapped.

**Do not `garage repair blocks`.** Table repair only.

**Do not `find` / `du` the NFS hex tree from the VM.** That wedges the
share. Delete leftover hex directories from TrueNAS, or leave them.

**Do not `chown -R` the NFS share.** Recursive `chown garage:garage` is
allowed **only** on the ext4 mount
(`/mnt/nfs/garage/data/.blocks-ext4`).

Wiping S3 drops Loki chunks and Mimir blocks. Import the existing
Loki and Mimir keys before `garage-bootstrap` mints new ones. The
`attic` bucket is unused
([2026-11-03-decommission-attic.md](../adr/2026-11-03-decommission-attic.md)).

## Empty cluster on the loop mount (2026-09-18)

This is what is live. Historical Garage objects were discarded.

1. Stop `garage-bootstrap`, Garage, Loki, and Mimir. Kill any rsync of
   the hex tree.

2. Aside LMDB, keep `node_key` / `node_key.pub`. Do not chown:

   ```bash
   ts=$(date -u +%Y%m%dT%H%M%SZ)
   mkdir /var/lib/garage/meta.wiped-$ts
   cd /var/lib/garage/meta
   mv db.lmdb cluster_layout data_layout snapshots \
     lifecycle_worker_state peer_list scrub_info \
     /var/lib/garage/meta.wiped-$ts/
   ```

3. Unmount the loop, `mkfs.ext4 -F -L garage-blocks` the image, remount
   `loop,noatime`, `chown garage:garage` the **mountpoint** only.

4. Set `data_dir = "/mnt/nfs/garage/data/.blocks-ext4"` (Nix after
   deploy; until then a bind-mount over `/etc/garage.toml`). Start
   Garage.

5. Layout, then import keys from the live secret files, then
   bootstrap:

   ```bash
   garage layout assign -z dc1 -c 1T <node-id>
   garage layout apply --version 1
   garage key import --yes -n loki-key …
   garage key import --yes -n mimir-key …
   garage key import --yes -n attic-key …
   systemctl start garage-bootstrap
   ```

   Attic's access key in `attic/env` may be JSON-quoted. Strip quotes
   before import. Do not print the secrets.

6. Truncate Attic `chunkref, object, nar, chunk` on `xcloud-postgres`
   while atticd is stopped, then start atticd and `attic-nar-proxy`.
   Restart Loki and Mimir.

7. Expect `/health` 200 and unauthenticated `:3902` 403.

## Optional: copy the hex tree instead of wiping

Only if you need the old objects. Exclude the image and the mountpoint.
Stop Garage for the final delta. Then chown the ext4 tree, not NFS
meta.

## Grow the image

`garage-loop-img-init` grows, never shrinks. It skips fsck and grow
while the image is mounted. To grow: set
`fleet.services.garage.loopbackImageSize`, stop Garage, unmount
`.blocks-ext4`, start `garage-loop-img-init.service`, remount, start
Garage. Confirm `df -h` on `.blocks-ext4`.

`GarageDiskSpaceLow` / `Critical` use `garage_local_disk_*` of this
ext4, not the NAS dataset.

## If the loop will not mount

`garage-loop-img-init.service` runs `e2fsck -fp` on the image unless it
is already mounted. Exit greater than 1 is a real fsck failure: do not
`resize2fs` or start Garage on that image. The unused NFS hex
directories are not a fallback after a wipe.
