# ADR: Garage metadata moves to LMDB

**Status:** accepted (2026-09-05); supersedes
[2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md)

## Context

[2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md) chose LMDB so
`attic push` could upload concurrently. `convert-db` failed twice on this
cluster (Permission denied on the idmapped metadata tree, then
`Invalid column type Integer at index: 1, name: v`), so Garage stayed on
`db_engine = "sqlite"` with `metadata_fsync = true` and the concurrency
premise was never true.

`metadata_fsync` does not make sqlite safe under concurrent writes, only
slower. A parallel `rpi4` fill on 2026-09-05 drove `proxmox-db-1` and
`proxmox-db-2` to 85-88% iowait and load 7. Garage stopped answering `:3902`
and `:3903` inside a 10s client timeout, `proxmox-lb` returned 503 for the
Garage health check, and `atticd` returned HTTP 500 for 113 uploads over an
hour while its unit stayed `active (running)`. The fill exited 1 after 32
minutes. sqlite serialized the writers rather than tearing the database, and
that queue starved every reader, which is Loki, Mimir, and Attic.

Both earlier `convert-db` blockers are gone. The idmap failure was
converting as `User=garage`. The column-type failure was against the
malformed database from the 2026-08-28/29 corruption, whose hand-written
merkle todo values are no longer present (`object:merkle_todo` is empty).

Re-tested `garage convert-db` 1.3.1 on `proxmox-db-1` against the
`2026-09-05T10:04:51Z` metadata snapshot, as
[2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md) required:

| Direction | Result | Time |
|-----------|--------|------|
| sqlite to LMDB | 62 tables, 370 MiB `data.mdb` | 2m59s |
| LMDB back to sqlite | 62 tables, identical counts | 5m23s |

`object:merkle_tree` 239006, `object:table` 187122, `block_ref:table`
171091, `version:table` 163803 in both directions. The reverse conversion is
what proves the LMDB is readable and complete rather than merely written.

## Decision

Garage uses `db_engine = "lmdb"`, upstream's default since 0.9.0.
`metadata_fsync` stays `true`. `lmdb_map_size` is left unset: upstream
defaults to 1 TiB on 64-bit, and it caps the database size rather than
allocating.

`garage-convert-sqlite-to-lmdb.service` converts once per node. It runs as
root because the metadata tree is idmapped to `nobody:nogroup` on disk, and
copies that ownership onto the result. `garage.service` requires it, so a
failed conversion leaves Garage down rather than starting it on an empty
LMDB and letting RF=2 replicate the emptiness onto the healthy peer. The
converted-from sqlite database is retired to `db.sqlite.migrated-<ts>`, not
deleted.

`ATTIC_PUSH_JOBS` defaults to 8 again, with `ATTIC_PUSH_BATCH_SIZE = 12` so a
failed batch retries on its own instead of failing a whole closure.

## Consequences

Deploy `proxmox-db-1` and then `proxmox-db-2`, each with
`ATTIC_PUSH_JOBS=1`, because their own fills run while they are still on
sqlite. Conversion takes roughly three minutes per node, during which that
node accepts no writes; with RF=2 and zone redundancy `maximum`, cluster
writes stop for the window, so Loki, Mimir, and Attic will 503. Do not
convert both nodes at once.

If conversion fails, Garage does not start and the node keeps its sqlite
database. Recovery, verification, and the space needed are in
[runbooks/garage-lmdb.md](../runbooks/garage-lmdb.md).

Metadata snapshots stay at 6h. Garage keeps the two most recent, and needs
up to 4x the database size in `metadata_dir` to rotate them.
