---
status: accepted
date: 2026-08-31
---

# rpi4 deploy runs on the Pi

## Context and Problem Statement

`rpi4` is the fleet's only `aarch64-linux` NixOS host. Building it from the
x86_64 GitLab runner (`proxmox-dev`) required `extra-platforms` plus qemu.
Unprivileged rootless Podman cannot register `binfmt_misc`, so Nix executed
aarch64 bash and failed with `Exec format error`.

## Decision Outcome

aarch64 **deploy** runs **on rpi4**, native. The Attic fill/verify steps
are gone
([2026-11-03-decommission-attic.md](2026-11-03-decommission-attic.md)).

1. `scripts/run-on-rpi4.sh` copies this checkout onto the Pi and runs
   `deploy-host.sh` there.
2. GitLab x86 deploy jobs stay on the proxmox-dev runner and only touch
   `x86_64-linux` hosts.
3. GitLab `deploy-rpi4` sshs to the Pi. It `allow_failure`s so a down Pi
   does not fail x86 deploys. It runs only on `main`.
4. `deploy-host.sh rpi4` from an x86_64 builder exits: it does not
   qemu-compile. On the Pi, switch is local.

Do not add `extra-platforms` or `qemu-user-static` to GitLab jobs. Do not
build `rpi4` on `proxmox-dev`.

### Consequences

The Pi compiles its own closure (slow, but correct) and substitutes from
`cache.nixos.org` plus the Raspberry Pi cachix. Operator path is
`./scripts/run-on-rpi4.sh ./scripts/deploy-host.sh rpi4`, not
`make deploy-host HOST=rpi4` from proxmox-dev.
