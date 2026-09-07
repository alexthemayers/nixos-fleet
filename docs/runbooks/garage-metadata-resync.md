# Runbook: restore Garage metadata on the single node

Use this when Garage on **`proxmox-observability`** 404s keys it used to
serve, panics on start (`resync.rs` torn queue), or reports a merkle TODO
that never drains. There is no peer. **Fix the node** so Attic/Mimir/Loki
can keep using `proxmox-observability:3902`.

Split metadata (200 on one db VM, 404 on the other) cannot happen on this
RF=1 layout. Ghost objects (listed `Content-Length`, empty body) still can.

Mimir pages `GarageMerkleTodoStuck` for a merkle TODO that is not draining,
and `GarageBlockResyncErrors` for ghost objects.

Do **not** `chown` `/var/lib/garage`. Do **not** `garage repair blocks` on
this cluster (`RepairWorker` unwrap panic, coredump). Do **not**
hand-roll `merkle_todo` values shorter than 32 bytes (coredump in
`merkle.rs` `Hash::try_from`).

A hypervisor hard reset can tear LMDB `block_local_resync_queue`.
Garage 1.3.1 then aborts on start:

```
panicked at src/block/resync.rs:265
range end index 8 out of range for slice of length 3
```

The queue key is `u64_be(when) || hash` (40 bytes). A 3-byte leftover is
a torn write. `garage repair clear-resync-queue` would drop that tree,
but the process never reaches the admin socket. Restore the latest Garage
snapshot (below). Do not edit LMDB by hand.

Nix substituters stay `http://proxmox-dev:8080/attic`. That is Caddy NAR
truncation, not this bug.

## Confirm

From a host with the Mimir or Attic S3 key, GET the object on the LB and
on obs-1 (never print the secret):

```bash
s3cli get anonymous/<ulid>/meta.json   # S3_URL endpoint=http://proxmox-observability:3902
```

A 404 on both is missing data, not a split. `garage stats`: large
`MklTodo` and journal `Messagepack decode error` on merkle/sync workers
mean table anti-entropy cannot run. Emptying merkle and
`garage repair -a --yes tables` then finishes in milliseconds and copies
nothing — there is no peer to copy from.

## Restore metadata from a Garage snapshot

`metadata_auto_snapshot_interval = 6h` keeps the two most recent snapshots
under `/var/lib/garage/meta/snapshots/`. That is the only consistent copy
on RF=1.

```bash
ssh root@proxmox-observability
systemctl stop garage
ts=$(date -u +%Y%m%dT%H%M%SZ)
mv /var/lib/garage/meta/db.lmdb /var/lib/garage/meta/db.lmdb.torn-$ts
# pick the newest snapshot directory; keep node_key and cluster_layout
cp -a /var/lib/garage/meta/snapshots/<latest> /var/lib/garage/meta/db.lmdb
# ownership stays nobody:nogroup on disk. Do not chown garage:garage.
systemctl start garage
garage status
```

If there is no snapshot, Garage will create an empty LMDB and every S3 key
is gone until you copy objects back or refill Attic / accept a Loki/Mimir
gap. Do not start an empty db while clients still write.

`garage repair -a --yes tables` is a no-op without a peer. Do not treat a
fast success as a repair.

## Ghost objects (200 then empty body)

HEAD/`meta.json` can 200 while GET of `index` or `chunks/000001` sends
`Content-Length` and zero bytes. Garage still has the object row; the
block data is gone (`resync: no node returned a valid block`). Do **not**
`garage repair blocks`.

A block whose data is gone is not recoverable, and Garage retries it
hourly forever because the refcount is still positive. That retry loop is
what `GarageBlockResyncErrors` reports. Identify the blast radius before
deleting anything: `block info` names the bucket and key, and the bucket
decides the remedy.

```bash
export GARAGE_RPC_SECRET_FILE=/run/secrets/garage/rpc_secret
garage block list-errors
garage block info <hash>          # Refcount, bucket, key
garage bucket info <bucket-id>    # loki / mimir / attic / web-assets
```

Confirm the block is dead rather than merely stuck: `garage block
retry-now <hash>`, then check the journal for `no node returned a valid
block` and an incremented error count. A block that still fails after
days of hourly retries is lost.

`garage block purge --yes <hash>...` marks the referencing versions and
objects deleted, which drops the refcount to 0. This is not `garage
repair blocks` and does not touch the RepairWorker. The data in those
objects is already unreadable, so purging trades a permanent error loop
for a clean 404. After purging, `block retry-now` the same hashes so the
resync worker processes them at refcount 0 and drops the queue entries,
instead of waiting up to an hour; `list-errors` then comes back empty.

For **Mimir**, treat the ULID as the unit, not a single Garage hash.

1. Confirm `proxmox-observability:3902` fails
   the same GET of `anonymous/<ulid>/index` after three tries. A listed
   `Content-Length` with curl exit 18 (`Transferred a partial file`)
   is a hole, not a Caddy hop. Range GETs of 1 MiB slices show which
   Garage blocks are gone.
2. If a GET returns the full `index`, stop. That is a transient 503,
   not this procedure.
3. If `index` and `chunks/000001` are holed, delete every key under
   that prefix (`meta.json`, `index`, `chunks/*`,
   `sparse-index-header`, `no-compact-mark.json`). `no-compact-mark`
   does not stop store-gateway or cleanup from reading `index`, so a
   mark-only fix leaves `MimirCompactorHasNotRun` firing forever.
4. Restart Mimir on obs-1 (`restartIfChanged = false`) so
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

Clients use `proxmox-observability:3902`. If Grafana still 500s, restart Mimir on
obs-1 (`restartIfChanged = false`) so store-gateway reloads the bucket
index. Substituters remain `http://proxmox-dev:8080/attic`.
