# ADR: Attic is tailnet HTTP and a deploy SPOF

**Status:** accepted (2026-08-29); host placement superseded
(2026-09-04)

## Context

Signatures on NARs prove integrity, not that the cache is highly available.
Public HTTPS for Attic was considered and rejected: the fleet already trusts
the tailnet for S3 and gossip.

## Decision

Attic is reachable on the tailnet at `http://proxmox-dev:8080/attic` (via
attic-nar-proxy so single-chunk NARs are 200 rather than a Garage 307). It is
an accepted SPOF for deploys. One `monolithic` node owns the cache
([2026-09-04-attic-on-proxmox-dev.md](2026-09-04-attic-on-proxmox-dev.md)).

## Consequences

If `proxmox-dev` or Garage is down, hosts cannot substitute or activate new
generations. Tokens stay in CI variables or `/root/.attic-token`, never in
git. Garage metadata is LMDB; `attic push` may run concurrent uploads
([2026-09-05-garage-lmdb-migration.md](2026-09-05-garage-lmdb-migration.md)).
