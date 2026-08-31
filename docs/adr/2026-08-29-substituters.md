# ADR: Substituters on builders vs deployed hosts

**Status:** accepted (2026-08-29)

## Context

NixOS merges `cache.nixos.org` into `nix.settings.substituters` unless forced
otherwise. Deployed hosts that can substitute from the public cache will do so
and skip Attic, so a later exclusive realize or copy-from-Attic 404s.

## Decision

- **Fill** (CI `fill-attic`, `make build`, first half of deploy): Attic plus
  `cache.nixos.org` (and the Raspberry Pi cachix) so missing NARs can be
  copied into Attic.
- **After fill** (verify, copy, switch, `nix develop` with a token): substituter
  **only** `http://proxmox-db-1:8080/attic`.
- **Deployed hosts** substitute only that same URL (`config/system.nix`
  `mkForce`). Not the LB: Caddy there can still truncate multi-chunk NARs.
- GitLab fill/verify/deploy uses the same db-1 URL. Exclusive realize is
  `scripts/verify-from-attic.sh` (`--max-jobs 0`, `fallback false`).

See [2026-08-30-attic-fill-then-exclusive.md](2026-08-30-attic-fill-then-exclusive.md).

## Consequences

Pushes use `--ignore-upstream-cache-filter` so paths that exist on
cache.nixos.org still land in Attic. Do not add the LB as a NAR substituter.
