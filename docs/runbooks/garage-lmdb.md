# Runbook: Garage sqlite → LMDB (parallel Attic uploads)

**Status:** current (2026-08-30). Do this **before** `make build` / any
`attic push` with `ATTIC_PUSH_JOBS` > 1. The fill scripts default to 8
jobs.

Garage metadata moves from sqlite (`synchronous=OFF`) to LMDB with
`metadata_fsync`. Each of `proxmox-db-1` and `proxmox-db-2` converts locally
on first start after this generation (`garage-convert-sqlite-to-lmdb.service`).

## Order

1. Fill and activate **only** the two db hosts (do not fill the rest of the
   fleet until both are healthy):

   ```bash
   # on proxmox-dev, after rsync. Still sqlite until switch converts.
   export ATTIC_TOKEN=$(cat /root/.attic-token)
   ATTIC_PUSH_JOBS=1 ATTIC_PUSH_BATCH_SIZE=12 ./scripts/deploy-from-attic.sh proxmox-db-1
   ATTIC_PUSH_JOBS=1 ATTIC_PUSH_BATCH_SIZE=12 ./scripts/deploy-from-attic.sh proxmox-db-2
   ```

   After each switch, convert runs while Garage is stopped, then Garage comes
   up on LMDB. Replication still writes to the peer: keep `-j 1` until **both**
   nodes show `db.lmdb`.

2. Confirm both nodes:

   ```bash
   for h in proxmox-db-1 proxmox-db-2; do
     ssh root@$h 'test -d /var/lib/garage/meta/db.lmdb && echo lmdb-ok; \
       systemctl is-active garage; curl -sf http://127.0.0.1:3903/health'
   done
   ```

   `/health` 200 and an unauthenticated S3 GET 403 mean writes are accepted
   again. Loki/Mimir/Attic will 503 for the convert window (zone redundancy
   `maximum`, RF=2).

3. Then fill and deploy the rest (`make build && make deploy-proxmox`, etc.).

## If convert fails

`garage convert-db` as `User=garage` hits Permission denied on `db.lmdb` (idmap).
The unit now converts as root and chowns to the on-disk owner.

`convert-db` on this sqlite can also fail with `Invalid column type Integer at
index: 1, name: v`. That abort leaves a partial `db.lmdb`; remove it and stay
on sqlite (`switch-to-configuration` of the previous generation) until convert
or a resync-from-peer path works.

Garage will not start (`requires` the convert unit). sqlite is still at
`meta/db.sqlite`. Read `journalctl -u garage-convert-sqlite-to-lmdb`. Roll the
host back with
[rollback.md](rollback.md) if the new generation cannot start.

Do not `chown` `/var/lib/garage` to `garage` (idmapped `nobody:nogroup`).

## If LMDB is malformed later

Stop **both** Garage units. On the bad node, move `meta/db.lmdb` aside. Start
the healthy node first, then the recovered one, so it resyncs (RF=2). Do not
`sqlite3 .recover` on LMDB. Snapshots live under `meta/snapshots/`.
