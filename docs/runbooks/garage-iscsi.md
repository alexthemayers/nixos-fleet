# Runbook: Garage on TrueNAS iSCSI

Use this on **`proxmox-observability`** when the iSCSI session will not
login, the LUN will not mount, or after growing the zvol.

**Do not dial the portal via MagicDNS.** `truenas-scale` is
`100.96.189.123` (MTU 1280). The initiator uses `192.168.3.9:3260`
(TrueNAS `enp6s16`).

**Do not `chown /var/lib/garage` to `garage`.** That tree is still
idmapped. `chown garage:garage` is required on `/mnt/iscsi/garage`
only.

**Do not `garage repair blocks`.** Table repair only.

**Do not `find` / `du` leftover NFS hex dirs from the VM.**

## Facts

| Item | Value |
|------|-------|
| Portal | `192.168.3.9:3260` |
| Target | `iqn.2005-10.org.freenas.ctl:garage` |
| LUN | 0 |
| Initiator | `iqn.2026-09.za.co.alexmayers:proxmox-observability` |
| Zvol | `ssd/garage-iscsi` (100G) |
| Mount | `/mnt/iscsi/garage` |
| `data_dir` | `/mnt/iscsi/garage/data` |
| `metadata_dir` | `/mnt/iscsi/garage/meta` |

TrueNAS SSH is closed. Create or inspect the target with QEMU guest
agent from the hypervisor:

```bash
ssh root@192.168.3.100
qm guest exec 100 -- /usr/bin/midclt call iscsi.target.query
qm guest exec 100 -- /usr/bin/midclt call iscsi.extent.query
qm guest exec 100 -- /usr/bin/midclt call pool.dataset.query '[["id","=","ssd/garage-iscsi"]]'
```

## First cutover (already applied 2026-09-18)

Nix logs in, mkfs if empty, mounts, copies LMDB from
`/var/lib/garage/meta` and blocks from `.blocks-ext4` if the dest is
empty, then starts Garage on the LUN. Leave `mountNfs = true` until
`/health` is 200 and `findmnt /mnt/iscsi/garage` shows the by-path
device. Then set `mountNfs = false`.

Expect `/health` 200 and unauthenticated `:3902` 403.

## Session will not login

```bash
systemctl status iscsi-login-garage.service iscsid.service
iscsiadm -m session
nc -z -w 2 192.168.3.9 3260
```

1. Portal down: TrueNAS `iscsitarget` service, zvol, or `enp6s16`.
2. Auth: initiator IQN must match the ACL. Changing
   `fleet.services.garage.iscsiInitiatorName` needs a TrueNAS initiator
   update.
3. Device missing: wait for
   `/dev/disk/by-path/ip-192.168.3.9:3260-iscsi-iqn.2005-10.org.freenas.ctl:garage-lun-0`.

## Grow the zvol

Stop Garage, unmount `/mnt/iscsi/garage`, logout. On TrueNAS (QGA):
raise `volsize` on `ssd/garage-iscsi`. Login, `resize2fs` the LUN,
remount, start Garage. `GarageDiskSpaceLow` reads this ext4.

## If the filesystem is torn

Do not mkfs a LUN that still has the only LMDB copy. Restore Garage's
own snapshot from `meta/snapshots/`
([garage-metadata-resync.md](garage-metadata-resync.md)).
