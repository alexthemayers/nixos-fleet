# Runbook: Garage LMDB metadata

The live node is **`proxmox-observability`** and already uses `db.lmdb`.
Do not convert a healthy node. Placement:
[garage on obs-1](../adr/2026-09-07-garage-on-obs-1.md). Decision:
[garage-lmdb-migration](../adr/2026-09-05-garage-lmdb-migration.md).

**Do not `chown /var/lib/garage` to `garage`.** The tree is idmapped and
reads `nobody:nogroup` on disk. Chowning it makes the database read-only
inside the unit.

**Do not `garage repair blocks` on this cluster.** Table repair only.
Merkle corrupt: empty + `garage repair -a --yes tables` is a no-op.
Rebuild merkle first
([garage-metadata-resync.md](garage-metadata-resync.md)).

Never push Attic in parallel against a node still on sqlite
(`ATTIC_PUSH_JOBS=1`). The live node is LMDB; the default of 8 is
correct.

## If sqlite reappears

`garage-convert-sqlite-to-lmdb.service` is `requiredBy` `garage.service`.
It is a no-op when `db.lmdb/data.mdb` exists. If conversion fails, Garage
does not start and the sqlite file stays in place.

Confirm free space (conversion writes a second full copy):

```bash
ssh root@proxmox-observability \
  'du -h /var/lib/garage/meta/db.sqlite 2>/dev/null; \
   df -h /var/lib/garage/meta | tail -1'
```

Journal:

```bash
ssh root@proxmox-observability \
  'journalctl -u garage-convert-sqlite-to-lmdb -n 60 --no-pager'
```

- `garage.service is still running` means the stop job had not finished.
  Stop Garage and start the unit again.
- Out of space: remove old `db.sqlite.{bak,corrupt,malformed,pre-recover}.*`
  and `db.sqlite.migrated-*` only after the cluster is verified.
- `Invalid column type Integer at index: 1, name: v` means the source
  database carries the 2026-08-28/29 corruption. Do not hand-write merkle
  todo values. Rebuild merkle on the source first
  ([garage-metadata-resync.md](garage-metadata-resync.md)).

A partial conversion is left in `db.lmdb.converting` and is removed on
the next attempt; the unit only publishes `db.lmdb` after `convert-db`
exits 0 and `data.mdb` is non-empty.

To convert by hand, with Garage stopped:

```bash
systemctl stop garage
garage convert-db -a sqlite -i /var/lib/garage/meta/db.sqlite \
  -b lmdb -o /var/lib/garage/meta/db.lmdb.converting
chown -R --reference=/var/lib/garage/meta/db.sqlite \
  /var/lib/garage/meta/db.lmdb.converting
mv /var/lib/garage/meta/db.lmdb.converting /var/lib/garage/meta/db.lmdb
mv /var/lib/garage/meta/db.sqlite \
  /var/lib/garage/meta/db.sqlite.migrated-manual
systemctl start garage
```

Leaving both `db.sqlite` and `db.lmdb` in `metadata_dir` is ambiguous;
the sqlite file must be renamed.

## If LMDB is malformed

There is no peer. Restore from a metadata snapshot, not table repair.
Snapshots live under `meta/snapshots/`; Garage keeps the two most recent.
Procedure: [garage-metadata-resync.md](garage-metadata-resync.md).

Do not `sqlite3 .recover` on LMDB.

To convert back to sqlite (only if you must, and with Garage stopped):

```bash
garage convert-db -a lmdb -i /var/lib/garage/meta/db.lmdb \
  -b sqlite -o /var/lib/garage/meta/db.sqlite
```

Then set `db_engine = "sqlite"` in
[`services/garage.nix`](../../services/garage.nix) and do not deploy
until you understand you cannot push Attic in parallel.
