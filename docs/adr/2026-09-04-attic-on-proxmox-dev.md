---
status: accepted
date: 2026-09-04
---

# Attic stack runs on proxmox-dev

## Context and Problem Statement

atticd `monolithic` chunks uploads in-process. That sat on
`proxmox-db-1` (2 GiB) next to Garage sqlite, so a fill starved both
daemons (accept queues backed up on `:3902`/`:3903`, SSH socket
activation hung). `proxmox-dev` is the 16 GiB builder. Garage must stay
on the db nodes (NFS data dirs, RF=2).

[2026-08-29-attic-monolithic.md](2026-08-29-attic-monolithic.md) still
requires exactly one `monolithic` node. This ADR only moves the host.

## Decision Outcome

The entire Attic stack (atticd + `attic-nar-proxy`) runs on
`proxmox-dev`. `proxmox-db-1` and `proxmox-db-2` run Garage only.

Substituters and `nix copy --from` use
`http://proxmox-dev:8080/attic`. Not the LB: Caddy on
`proxmox-lb:8080` can still truncate multi-chunk NARs.

First switch of `proxmox-dev` after this move fills and proves against
the old generation (`ATTIC_ENDPOINT=http://proxmox-db-1:8080`) while
db-1 still has atticd, then switches locally. After that, drop Attic
from the db nodes. `ATTIC_COPY_FROM_BUILDER=1` remains the hatch if the
old cache cannot accept a push.

### Consequences

`proxmox-dev` is the Attic deploy SPOF (and still the x86 builder).
Garage write quorum is unchanged. Mint tokens with `atticadm` on
`proxmox-dev`. `attic/env` lives in `secrets/proxmox-dev/`.
