# Runbook: Garage sqlite to LMDB

Convert Garage metadata from sqlite to LMDB, one node at a time. Decision and
the verification that unblocked it:
[garage-lmdb-migration ADR](../adr/2026-09-05-garage-lmdb-migration.md).

**Convert one node at a time.** RF=2 with zone redundancy `maximum` needs both
zones for writes. Each conversion takes about three minutes on a 400 MiB
database, and cluster writes stop for that window: Loki, Mimir, and Attic
will 503. Do not deploy both db hosts in one pass.

**Push serially for these two deploys.** `proxmox-db-1` and `proxmox-db-2`
fill their own closures while still on sqlite, so pass
`ATTIC_PUSH_JOBS=1 ATTIC_PUSH_BATCH_SIZE=12`. A parallel push against sqlite
is what stalled the cluster on 2026-09-05.

**Garage will not start if conversion fails.** That is deliberate: starting on
an empty LMDB would let RF=2 replicate the emptiness onto the healthy peer.
The node keeps its sqlite database; see "If conversion fails".

**Do not `chown /var/lib/garage` to `garage`.** The tree is idmapped and reads
`nobody:nogroup` on disk. Chowning it makes the database read-only inside the
unit. The conversion unit runs as root and copies the on-disk ownership.

## Before you start

1. Confirm free space on the metadata filesystem. Conversion writes a second
   full copy and keeps the original, so budget twice the database size:

   ```bash
   for h in proxmox-db-1 proxmox-db-2; do
     ssh root@$h 'du -h /var/lib/garage/meta/db.sqlite; df -h /var/lib/garage/meta | tail -1'
   done
   ```

   The unit refuses to convert rather than filling the root filesystem. Old
   `db.sqlite.{bak,corrupt,malformed,pre-recover}.*` files from earlier
   incidents can be removed to reclaim space if it is short.

2. Confirm the cluster is healthy first. Do not start a conversion on a
   cluster that is already degraded:

   ```bash
   for h in proxmox-db-1 proxmox-db-2; do
     printf '%s ' $h
     ssh root@$h 'curl -sf -o /dev/null -w "health=%{http_code} " http://127.0.0.1:3903/health; \
       systemctl is-active garage'
   done
   ```

   Expect `health=200` and `active` on both.

3. Take a fresh metadata snapshot so there is a known-good copy from just
   before the change:

   ```bash
   ssh root@proxmox-db-1 'GARAGE_RPC_SECRET_FILE=/run/secrets/garage/rpc_secret garage meta snapshot'
   ssh root@proxmox-db-2 'GARAGE_RPC_SECRET_FILE=/run/secrets/garage/rpc_secret garage meta snapshot'
   ```

## Convert

1. Deploy `proxmox-db-1` only, from `proxmox-dev`:

   ```bash
   export ATTIC_TOKEN=$(cat /root/.attic-token)
   ATTIC_PUSH_JOBS=1 ATTIC_PUSH_BATCH_SIZE=12 ./scripts/deploy-from-attic.sh proxmox-db-1
   ```

   The switch stops Garage, runs `garage-convert-sqlite-to-lmdb.service`, then
   starts Garage on LMDB.

2. Verify `proxmox-db-1` before touching db-2:

   ```bash
   ssh root@proxmox-db-1 'systemctl status garage-convert-sqlite-to-lmdb --no-pager | tail -20; \
     ls -la /var/lib/garage/meta/db.lmdb/; \
     systemctl is-active garage; \
     curl -sf -o /dev/null -w "health=%{http_code}\n" http://127.0.0.1:3903/health'
   ```

   Expect `data.mdb` present, `garage` active, and `health=200`. An
   unauthenticated S3 `GET http://127.0.0.1:3902/` returning 403 means writes
   are being accepted again. The retired database stays as
   `db.sqlite.migrated-<ts>`.

3. Confirm the converted node rejoined and holds its partitions:

   ```bash
   ssh root@proxmox-db-1 'GARAGE_RPC_SECRET_FILE=/run/secrets/garage/rpc_secret garage status'
   ```

   Both nodes must appear. Do not continue while db-1 shows as down from
   db-2's view.

4. Repeat steps 1 to 3 for `proxmox-db-2`.

5. Only once both nodes show `db.lmdb` and `health=200`, resume normal fills.
   `ATTIC_PUSH_JOBS` defaults to 8 again and no longer needs an override.

## If conversion fails

Garage will not start: `garage.service` requires the conversion unit. The
node still has its sqlite database, so nothing is lost.

```bash
ssh root@proxmox-db-1 'journalctl -u garage-convert-sqlite-to-lmdb -n 60 --no-pager'
```

- `garage.service is still running` means the stop job had not finished. Stop
  Garage and start the unit again.
- Out of space: reclaim from the old `db.sqlite.*` files listed above.
- `Invalid column type Integer at index: 1, name: v` means the source database
  carries the 2026-08-28/29 corruption again. Do not hand-write merkle todo
  values. Rebuild merkle on the source first
  ([garage-metadata-resync.md](garage-metadata-resync.md)).

A partial conversion is left in `db.lmdb.converting` and is removed on the
next attempt; the unit only publishes `db.lmdb` after `convert-db` exits 0
and `data.mdb` is non-empty.

To get the node running again on sqlite, roll back to the previous generation
with [rollback.md](rollback.md).

To convert by hand on the node, with Garage stopped:

```bash
systemctl stop garage
garage convert-db -a sqlite -i /var/lib/garage/meta/db.sqlite \
  -b lmdb -o /var/lib/garage/meta/db.lmdb.converting
chown -R --reference=/var/lib/garage/meta/db.sqlite /var/lib/garage/meta/db.lmdb.converting
mv /var/lib/garage/meta/db.lmdb.converting /var/lib/garage/meta/db.lmdb
mv /var/lib/garage/meta/db.sqlite /var/lib/garage/meta/db.sqlite.migrated-manual
systemctl start garage
```

Leaving both `db.sqlite` and `db.lmdb` in `metadata_dir` is ambiguous; the
sqlite file must be renamed.

## If LMDB is malformed later

Stop **both** Garage units. On the bad node, move `meta/db.lmdb` aside. Start
the healthy node first, then the recovered one, so it resyncs (RF=2). Do not
`sqlite3 .recover` on LMDB. Snapshots live under `meta/snapshots/`, and
Garage keeps only the two most recent.

To go back to sqlite, convert in reverse (proven in both directions) and set
`db_engine = "sqlite"` in [`services/garage.nix`](../../services/garage.nix):

```bash
garage convert-db -a lmdb -i /var/lib/garage/meta/db.lmdb \
  -b sqlite -o /var/lib/garage/meta/db.sqlite
```
