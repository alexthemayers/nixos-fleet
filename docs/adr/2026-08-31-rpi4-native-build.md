# ADR: rpi4 fill and deploy run on the Pi

**Status:** accepted (2026-08-31)

## Context

`rpi4` is the fleet's only `aarch64-linux` NixOS host. Filling it from the
x86_64 GitLab runner (`proxmox-dev`) required `extra-platforms` plus qemu.
Unprivileged rootless Podman cannot register `binfmt_misc`, so Nix executed
aarch64 bash and failed with `Exec format error`. Emulating Attic's crane
hooks on x86_64 is the wrong builder anyway.

## Decision

aarch64 **fill**, **verify**, and **deploy** run **on rpi4**, native:

1. `scripts/run-on-rpi4.sh` copies this checkout onto the Pi and runs the
   same `build.sh` / `verify-from-attic.sh` / `deploy-from-attic.sh` there.
2. GitLab `fill-attic` / `verify-from-attic` / the x86 deploy jobs stay on
   the proxmox-dev runner and only touch `x86_64-linux` hosts.
3. GitLab `fill-attic-rpi4`, `verify-from-attic-rpi4`, and `deploy-rpi4`
   ssh to the Pi. They `allow_failure` so a down Pi does not fail x86 deploys.
4. `deploy-from-attic.sh rpi4` from an x86_64 builder exits: it does not
   qemu-compile. On the Pi, when `hostname` is `rpi4`, switch is local after
   exclusive realize (no ssh-to-self).

Do not add `extra-platforms` or `qemu-user-static` to GitLab jobs. Do not
fill `packages.aarch64-linux.*` or `rpi4` on `proxmox-dev`.

## Consequences

The Pi compiles its own closure (slow, but correct). Fill on the Pi may use
`cache.nixos.org` via the scripts' builder substituters; the Pi's `nix.conf`
stays Attic-only. Operator path is `./scripts/run-on-rpi4.sh`, not
`make deploy-from-attic HOST=rpi4` from proxmox-dev.
