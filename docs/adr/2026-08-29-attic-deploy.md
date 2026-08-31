# ADR: Deploy from Attic, then switch-to-configuration

**Status:** accepted (2026-08-29)

## Context

`deploy-rs` copies closures from the builder store. That couples every target
to the builder remaining up and to `nix copy` over SSH of paths the target
could instead substitute.

## Decision

Production activation is:

1. **Fill** Attic: realize on a builder with public substituters if a path is
   missing, then `attic push` the closure (`ATTIC_PUSH_JOBS`, default 8)
2. **Exclusive realize** (`--max-jobs 0`, Attic only)
3. `nix copy --from http://proxmox-db-1:8080/attic` onto the target
4. `switch-to-configuration switch` on the target

Public substituters are not used after fill. Tightened by
[2026-08-30-attic-fill-then-exclusive.md](2026-08-30-attic-fill-then-exclusive.md).

`make deploy-rs` and `magicRollback` remain as a fallback. `gaming` uses the
same Attic path as the rest of the fleet; `make reboot-all` still skips it.

## Consequences

A missing NAR is a failed deploy, not a silent compile on the target.
`ATTIC_COPY_FROM_BUILDER=1` is a bootstrap hatch for putting attic-nar-proxy
onto the cache hosts themselves. See [deployments.md](../deployments.md).
