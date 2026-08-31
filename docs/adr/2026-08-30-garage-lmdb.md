# ADR: Garage LMDB so Attic uploads can run in parallel

**Status:** superseded in part (2026-08-30)

`convert-db` on this cluster failed (idmap Permission denied, then sqlite
column type `v`). Garage stays `db_engine = "sqlite"` with
`metadata_fsync = true` (`PRAGMA synchronous = NORMAL`). Parallel
`attic push` (`ATTIC_PUSH_JOBS`) is allowed against that; do not switch
to LMDB until convert succeeds on a copy of `db.sqlite`.

## Context

`attic push` was serial (`-j 1`, batches of 12) because Garage stored
metadata in sqlite with the default `metadata_fsync = false` (`PRAGMA
synchronous = OFF`). SQLite locking still serializes writers; it does not
fsync. A PutObject burst malformed `db.sqlite` on both db nodes.

## Decision

- Garage `db_engine = "lmdb"` (upstream default) and `metadata_fsync = true`.
- First start of each node converts `/var/lib/garage/meta/db.sqlite` to
  `db.lmdb` (`garage-convert-sqlite-to-lmdb.service`) and moves sqlite aside.
- `attic push` uses `ATTIC_PUSH_JOBS` (default 8) and pushes a closure in one
  invocation.

Deploy `proxmox-db-1` and `proxmox-db-2` **before** the next `make build`.
Write quorum needs both zones; convert takes that node down briefly.

## Consequences

Unclean shutdown can still corrupt LMDB; `metadata_auto_snapshot_interval`
stays at 6h. Recover a bad node by removing `db.lmdb` and letting RF=2
resync, not `sqlite3 .recover`. See
[runbooks/garage-lmdb.md](../runbooks/garage-lmdb.md).
