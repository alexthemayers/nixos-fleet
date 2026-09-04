# ADR: One Attic monolithic node

**Status:** accepted (2026-08-29); host placement superseded
(2026-09-04)

## Context

atticd `monolithic` owns sqlite metadata and chunking. Running two
monolithic nodes against the same Garage bucket tears that database.

## Decision

Exactly one `monolithic` Attic. Substituters and `nix copy --from` use
that node (attic-nar-proxy on `:8080`, atticd on `127.0.0.1:8081`). Do
not add a second monolithic.

The host is `proxmox-dev`
([2026-09-04-attic-on-proxmox-dev.md](2026-09-04-attic-on-proxmox-dev.md)).
Garage stays on the db nodes.

## Consequences

The Attic host is a deploy SPOF
([2026-08-29-attic-tailnet.md](2026-08-29-attic-tailnet.md)). Garage
metadata is LMDB; parallel `attic push` is
[2026-08-30-garage-lmdb.md](2026-08-30-garage-lmdb.md).
