# Runbook: resync Garage metadata from the peer

Use this when one Garage node **404s keys the other returns 200** (LB
round-robin then fails half the time). That is split metadata.
**Fix the cluster** so Attic/Mimir/Loki can keep using `proxmox-lb:3902`.
Do not pin those clients at `proxmox-db-1:3902`.

Mimir pages `GarageMerkleTodoStuck` for a merkle TODO that is not draining,
and `GarageBlockResyncErrors` for ghost objects (200 then empty body).

Do **not** `chown` `/var/lib/garage`. Do **not** `garage repair blocks` on
this cluster (`RepairWorker` unwrap panic, coredump). Do **not**
hand-roll `merkle_todo` values shorter than 32 bytes (coredump in
`merkle.rs` `Hash::try_from`).

A hypervisor hard reset can also tear LMDB `block_local_resync_queue`.
Garage 1.3.1 then aborts on start:

```
panicked at src/block/resync.rs:265
range end index 8 out of range for slice of length 3
```

The queue key is `u64_be(when) || hash` (40 bytes). A 3-byte leftover is
a torn write. `garage repair clear-resync-queue` would drop that tree,
but the process never reaches the admin socket. Treat the node as
lagging: move `db.lmdb` aside (keep `node_key` / `cluster_layout`) and
`garage repair --yes -a tables` from the peer. Do not edit LMDB by hand.

Nix substituters stay `http://proxmox-dev:8080/attic`. That is Caddy NAR
truncation, not this bug.

## Confirm

From a host with the Mimir or Attic S3 key, GET the same object on both
nodes (never print the secret):

```bash
# 200 on db-1, 404 on db-2 → db-2 is the lagging node
s3cli get anonymous/<ulid>/meta.json   # S3_URL endpoint=http://proxmox-db-1:3902
s3cli get anonymous/<ulid>/meta.json   # endpoint=http://proxmox-db-2:3902
```

`garage stats`: large `MklTodo` and journal `Messagepack decode error` on
merkle/sync workers mean table anti-entropy cannot run. Emptying the lagging
node and `garage repair -a --yes tables` then finishes in milliseconds and
copies nothing.

## Rebuild merkle on the source node first

Table keys are `hash(partition_key)+sort_key` and must be **at least 32
bytes**. A handful of sqlite rows are shorter garbage; enqueueing them
coredumps (`k[0..32]`). `merkle_todo` **value** is blake2b-512 of the item
blob, first 32 bytes (not blake2b-256).

Stop Garage on the **source** node (the one that 200s). Checkpoint WAL.
Using sqlite3 already in the Nix store (do not `nix-shell -p sqlite`):

1. `DELETE` `tree_<name>_COLON_merkle_tree` and `tree_<name>_COLON_merkle_todo`
   for `object`, `version`, `block_ref`.
2. For each table row with `length(k) >= 32`, insert `(k, blake2b512(v)[:32])`
   into `merkle_todo`.
3. `chown nobody:nogroup` the sqlite file. Start Garage.

Wait until Merkle workers are Busy with **zero decode errors** and `MklItems`
is rising. Table repair can run in parallel once that is true. Re-run
`garage repair -a --yes tables` as `MklItems` grows: a one-shot while most
partitions still have empty merkle roots copies only the finished ones and
then idles (`object sync` queue 0). If you repair while merkle still
decodes as garbage, it finishes in milliseconds and copies nothing. Full
drain of `MklTodo` can take tens of minutes (workers throttle).

## Empty the lagging node and resync tables

Keep `node_key` / `node_key.pub` / `cluster_layout` so the node ID does not
change. Move only the live metadata database. Writes need both zones; this
window 503s S3.

On the **lagging** node (example: db-2):

```bash
systemctl stop garage
cd /var/lib/garage/meta
ts=$(date -u +%Y%m%dT%H%M%SZ)
mkdir "wipe-resync-${ts}"
mv db.lmdb "wipe-resync-${ts}/"
systemctl start garage
curl -sf http://127.0.0.1:3903/health   # 200; garage status still shows the old ID
```

`garage-convert-sqlite-to-lmdb.service` no-ops here: with neither `db.lmdb`
nor `db.sqlite` present it exits 0 and Garage creates an empty LMDB to
resync into. On a node not yet converted, move `db.sqlite` plus its
`-wal`/`-shm` instead.

From **either** node, with `GARAGE_RPC_SECRET_FILE` from the unit environment:

```bash
garage repair --yes -a tables
```

Watch `garage stats` (`object` Items on the recovered node rising toward the
peer) and repeat the GET until **both** nodes return 200. Then GET through
`http://proxmox-lb:3902` several times (round-robin).

Snapshots under `meta/snapshots/` are the other official path if you would
rather roll the lagging node to a known file instead of empty+resync
(Garage recovering docs, option 2).

## Ghost objects (200 then empty body)

HEAD/`meta.json` can 200 while GET of `index` or `chunks/000001` sends
`Content-Length` and zero bytes. Garage still has the object row; the
block data is gone (`resync: no node returned a valid block`). Do **not**
`garage repair blocks`.

A block whose data is gone from every replica is not recoverable, and
Garage retries it hourly forever because the refcount is still positive.
That retry loop is what `GarageBlockResyncErrors` reports. Identify the
blast radius before deleting anything: `block info` names the bucket and
key, and the bucket decides the remedy.

```bash
export GARAGE_RPC_SECRET_FILE=/run/secrets/garage/rpc_secret
garage block list-errors
garage block info <hash>          # Refcount, bucket, key
garage bucket info <bucket-id>    # loki / mimir / attic / web-assets
```

Confirm the block is dead rather than merely stuck: `garage block
retry-now <hash>`, then check the journal for `no node returned a valid
block` and an incremented error count. A block that both nodes fail on
across days of hourly retries is lost.

`garage block purge --yes <hash>...` marks the referencing versions and
objects deleted, which drops the refcount to 0. Run it once from either
node; it applies cluster-wide over RPC. This is not `garage repair
blocks` and does not touch the RepairWorker. The data in those objects is
already unreadable, so purging trades a permanent error loop for a clean
404. After purging, `block retry-now` the same hashes so the resync
worker processes them at refcount 0 and drops the queue entries, instead
of waiting up to an hour; `list-errors` then comes back empty on **both**
nodes.

For **Mimir**, treat the ULID as the unit, not a single Garage hash.

1. Confirm both `proxmox-db-1:3902` and `proxmox-db-2:3902` fail the
   same GET of `anonymous/<ulid>/index` after three tries. A listed
   `Content-Length` with curl exit 18 (`Transferred a partial file`)
   is a hole, not a Caddy hop. Range GETs of 1 MiB slices show which
   Garage blocks are gone.
2. If any replica returns the full `index`, stop. That is split
   metadata or a transient 503, not this procedure.
3. If both replicas fail and `chunks/000001` is holed too, delete
   every key under that prefix (`meta.json`, `index`, `chunks/*`,
   `sparse-index-header`, `no-compact-mark.json`). `no-compact-mark`
   does not stop store-gateway or cleanup from reading `index`, so a
   mark-only fix leaves `MimirCompactorHasNotRun` firing forever.
4. Restart Mimir on both obs nodes (`restartIfChanged = false`) so
   store-gateway drops cached metas. Compaction then works on the
   remaining prefixes. A full run can take hours with
   `compaction_concurrency = 1` after a long stall.

Do not `garage repair blocks`. Historical samples in those ULIDs are
already gone; newer readable blocks still compact. Decision:
[2026-09-05-mimir-delete-lost-blocks.md](../adr/2026-09-05-mimir-delete-lost-blocks.md).

For **Loki** (`fake/` keys are the default single tenant; `index_NNNNN`
are TSDB indexes) purge is the whole fix. A lost chunk drops those log
lines and a lost index file narrows queries over that period, both of
which already happened when the data went missing. Loki needs no restart.

For **Attic**, purge deletes the NAR chunk and leaves atticd's Postgres
advertising a narinfo it cannot serve, which fails builds rather than
missing a log line. That is a different repair: the store path has to be
rebuilt and re-pushed. Note that atticd returning `NoSuchKey` is *not*
this bug at all — that is an object row Garage never had, so it will
never appear in `list-errors`.

## Afterward

Clients stay on `proxmox-lb:3902`. If Grafana still 500s, restart Mimir on
both obs nodes (`restartIfChanged = false`) so store-gateway reloads the
bucket index. Substituters remain `http://proxmox-dev:8080/attic`.
