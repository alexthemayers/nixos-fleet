---
status: superseded by [2026-09-05-garage-lmdb-migration.md](2026-09-05-garage-lmdb-migration.md)
date: 2026-09-05
---

# Garage LMDB so Attic uploads can run in parallel

`convert-db` failed when this was written (idmap Permission denied, then
sqlite column type `v`), so Garage ran `db_engine = "sqlite"` with
`metadata_fsync = true` while the parallel `ATTIC_PUSH_JOBS = 8` default
below stayed in the scripts. That combination stalled the cluster on
2026-09-05. Conversion has since been verified in both directions; the
migration ADR carries the current decision and the procedure.

## Context and Problem Statement

`attic push` was serial (`-j 1`, batches of 12) because Garage stored
metadata in sqlite with the default `metadata_fsync = false` (`PRAGMA
synchronous = OFF`). SQLite locking still serializes writers; it does not
fsync. A PutObject burst malformed `db.sqlite` on both db nodes.

## Decision Outcome

Superseded. Recorded as originally written; the conversion never ran.

- Garage `db_engine = "lmdb"` (upstream default) and `metadata_fsync = true`.
- First start of each node converts `/var/lib/garage/meta/db.sqlite` to
  `db.lmdb` (`garage-convert-sqlite-to-lmdb.service`) and moves sqlite aside.
- `attic push` uses `ATTIC_PUSH_JOBS` (default 8) and pushes a closure in one
  invocation.

Deploy `proxmox-db-1` and `proxmox-db-2` **before** the next `make build`.
Write quorum needs both zones; convert takes that node down briefly.

### Consequences

Unclean shutdown can still corrupt LMDB; `metadata_auto_snapshot_interval`
stays at 6h. Recover a bad node by removing `db.lmdb` and letting RF=2
resync, not `sqlite3 .recover`. See
[runbooks/garage-lmdb.md](../runbooks/garage-lmdb.md).
