---
status: accepted
date: 2026-08-30
---

# Fill Attic from public substituters, then deploy exclusively from it

## Context and Problem Statement

[2026-08-29-attic-deploy.md](2026-08-29-attic-deploy.md) copies the host
closure from Attic onto the target, but the **builder** still listed
`cache.nixos.org` during `nix build` in the same deploy command. On
`proxmox-dev`, host `nix.conf` is Attic-only, so `nix develop` (needed to get
the `attic` CLI) compiled stdenv from source and hit a tinycc FOD mismatch.

A deploy that can still fetch from the public cache after Attic is populated
is not an Attic-exclusive deploy.

## Decision Outcome

Two phases, never mixed:

1. **Fill.** Realize host closures, `packages.<system>.attic`,
   `packages.<system>.ci-tools`, and `devShells.<system>.default` with builder substituters (Attic +
   `cache.nixos.org` + the Raspberry Pi cachix) **on a builder of that
   system** (`proxmox-dev` for x86_64, `rpi4` for aarch64). `attic push
   --ignore-upstream-cache-filter` so paths that exist upstream still land in
   Attic. Public substituters are allowed **only** here.
2. **Exclusive.** Realize (`--max-jobs 0`, `fallback false`), `nix copy
   --from http://proxmox-dev:8080/attic`, `switch-to-configuration`, and
   `nix develop` after fill use **only** that Attic URL.

`scripts/deploy-from-attic.sh` does fill then exclusive for that host, unless
`ATTIC_SKIP_FILL=1` (GitLab after verify). `scripts/build.sh` is fill only.
`scripts/verify-from-attic.sh` checks narinfos on Attic; it does not download
host NARs. Scripts realize `.#attic` themselves; they do not wrap in
`nix develop`.

Deployed-host `nix.conf` stays Attic-only. Do not add `cache.nixos.org` there.

### Consequences

The first `attic` CLI on an Attic-only builder comes from fill (`nix build
.#attic` with builder substituters), then that closure is pushed so later
`nix develop` and exclusive realize can use Attic. `ATTIC_COPY_FROM_BUILDER=1`
remains the hatch for the cache hosts themselves.
