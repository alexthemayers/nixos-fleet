# ADR: Delete Mimir ULIDs whose Garage blocks are gone on every replica

**Status:** accepted (2026-09-05)

## Context

The Mimir compactor had never completed a run
(`cortex_compactor_last_successful_run_timestamp_seconds = 0` on both
obs nodes). Logs showed `unexpected EOF` and `Key not found` on
`anonymous/<ulid>/index`. Twenty-three of those ULIDs already carried
`no-compact-mark.json` (`reason=critical`), the remedy in
[garage-metadata-resync.md](../runbooks/garage-metadata-resync.md), and
the planner still failed: store-gateway and cleanup keep reading every
`index` that `meta.json` advertises.

On 2026-09-05, 31 of 144 prefixes in the `mimir` bucket failed a
three-try GET of `index` on both `proxmox-db-1:3902` and
`proxmox-db-2:3902`. Range GETs of the same objects returned some 1 MiB
Garage blocks intact and others as zero bytes. A full GET died at the
first hole with curl exit 18 (`Transferred a partial file`) in a few
milliseconds, including when talking straight to a db node with no
Caddy and no LB. That is the same error string the fleet has attributed
to Caddy on `proxmox-lb:8080`; here the cause was missing replica
blocks, not the hop.

`meta.json` was readable on all 31. The covered window is 2026-08-04
14:00 UTC through 2026-08-25 14:00 UTC. ULID write times stop on
2026-08-25. No newer prefix failed the same test. Chunks were holed
too, so nothing in those ULIDs was salvageable. RF=2 did not help:
both nodes lost the same offsets.

Those samples were already unqueryable. Leaving the prefixes in the
bucket kept every compaction cycle, and every store-gateway sync,
failing on them.

## Decision

When a Mimir ULID's `index` and `chunks/000001` are unreadable on every
Garage replica after retries, delete the whole prefix. Do not stop at
`no-compact-mark.json`. Confirm both nodes, list the keys, delete only
that set, then restart Mimir so store-gateway drops cached metas.

Do not `garage repair blocks`. Do not delete a ULID that still has a
fully readable `index` on either replica.

## Consequences

The 31 prefixes (136 keys) were deleted on 2026-09-05. 112 readable
prefixes remain. After the Mimir restart, the current PIDs show zero
`unexpected EOF` / `get TOC from object storage` errors. The
compactor is merging healthy groups (`compact blocks` on 6-block
jobs). A full run has not finished yet: `compaction_concurrency = 1`
and the backlog is weeks of uncompacted ranges. Transient Garage 503s
under that write load can fail a single job; those retry.

Metrics that lived only in the deleted ULIDs stay gone. Grafana range
queries over early–mid August will have gaps there. Newer blocks and
the ingesters are unaffected.

The same August event is the likely cause of Attic `NoSuchKey` on
single-block chunks; that is a separate repair (rebuild and re-push).
The Caddy `:8080` substituter landmine is not flipped here — only
noted that a holed Garage object produces the same curl exit 18.

Procedure:
[garage-metadata-resync.md](../runbooks/garage-metadata-resync.md).
