# Runbook: resync Garage metadata from the peer

Use this when one Garage node **404s keys the other returns 200** (LB
round-robin then fails half the time). That is split sqlite metadata.
**Fix the cluster** so Attic/Mimir/Loki can keep using `proxmox-lb:3902`.
Do not pin those clients at `proxmox-db-1:3902`.

Do **not** `chown` `/var/lib/garage`. Do **not** `garage repair blocks` on
this sqlite cluster (`RepairWorker` unwrap panic, coredump). Do **not**
hand-roll `merkle_todo` values shorter than 32 bytes (coredump in
`merkle.rs` `Hash::try_from`).

Nix substituters stay `http://proxmox-db-1:8080/attic`. That is Caddy NAR
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
change. Move only the live sqlite (+ WAL/SHM). Writes need both zones; this
window 503s S3.

On the **lagging** node (example: db-2):

```bash
systemctl stop garage
cd /var/lib/garage/meta
ts=$(date -u +%Y%m%dT%H%M%SZ)
mkdir "wipe-resync-${ts}"
mv db.sqlite db.sqlite-wal db.sqlite-shm "wipe-resync-${ts}/"
systemctl start garage
curl -sf http://127.0.0.1:3903/health   # 200; garage status still shows the old ID
```

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
`garage repair blocks`. For Mimir, PUT
`anonymous/<ulid>/no-compact-mark.json` (`version` 1, `reason` `critical`)
so the split-and-merge planner skips that block. Historical samples in
those ULIDs are lost; newer readable blocks still compact.

## Afterward

Clients stay on `proxmox-lb:3902`. If Grafana still 500s, restart Mimir on
both obs nodes (`restartIfChanged = false`) so store-gateway reloads the
bucket index. Substituters remain `http://proxmox-db-1:8080/attic`.
