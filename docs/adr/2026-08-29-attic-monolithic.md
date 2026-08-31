# ADR: One Attic monolithic node

**Status:** accepted (2026-08-29)

## Context

atticd `monolithic` owns sqlite metadata and chunking. Running two
monolithic nodes against the same Garage bucket tears that database.
`proxmox-db-2` already runs `api-server` for read fan-out.

## Decision

Exactly one `monolithic` Attic: `proxmox-db-1`. Substituters and
`nix copy --from` use db-1 (attic-nar-proxy on `:8080`, atticd on
`127.0.0.1:8081`). Do not add a second monolithic.

## Consequences

db-1 is a deploy SPOF
([2026-08-29-attic-tailnet.md](2026-08-29-attic-tailnet.md)). Garage metadata
is LMDB; parallel `attic push` is
[2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md).
