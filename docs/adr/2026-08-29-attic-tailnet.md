# ADR: Attic is tailnet HTTP and a deploy SPOF

**Status:** accepted (2026-08-29)

## Context

Signatures on NARs prove integrity, not that the cache is highly available.
Public HTTPS for Attic was considered and rejected: the fleet already trusts
the tailnet for S3 and gossip.

## Decision

Attic is reachable on the tailnet at `http://proxmox-db-1:8080/attic` (via
attic-nar-proxy so single-chunk NARs are 200 rather than a Garage 307). It is
an accepted SPOF for deploys. `proxmox-db-2` runs `api-server` only; one
`monolithic` node owns the cache.

## Consequences

If db-1 or Garage is down, hosts cannot substitute or activate new
generations. Tokens stay in CI variables or `/root/.attic-token`, never in
git. Garage metadata is LMDB; `attic push` may run concurrent uploads
([2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md)).
