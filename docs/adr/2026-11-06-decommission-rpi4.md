---
status: accepted
date: 2026-11-06
---

# Decommission rpi4; no aarch64-linux NixOS hosts

## Context and Problem Statement

`rpi4` was the fleet's only `aarch64-linux` NixOS host and the USB
off-host backup target. It has been unreachable and is decommissioned.
Keeping the flake input, deploy path, scrapes, and "temporary" backup
docs implies it will return.

## Decision Drivers

* One less architecture and flake input to maintain
* Backups already land on `backup-relay@proxmox-dev`
* Live docs must not describe a host that does not exist

## Considered Options

* Keep rpi4 in the flake paused until hardware returns
* Remove rpi4 and aarch64-linux from the flake; permanent backup-relay
* Replace the Pi with another aarch64 box immediately

## Decision Outcome

Chosen option: "Remove rpi4 and aarch64-linux from the flake; permanent
backup-relay", because the hardware is gone and the builder already holds
Postgres and GitLab dumps.

1. Delete `hosts/rpi4/`, `nixosConfigurations.rpi4`, `deploy.nodes.rpi4`,
   the `nixos-raspberrypi` input, `scripts/run-on-rpi4.sh`, and
   `secrets/rpi4`.
2. NixOS fleet hosts are `xcloud-caddy`, `xcloud-postgres`, and `gaming`.
   `aarch64-darwin` stays for the laptop.
3. Off-host backups stay at
   `backup-relay@proxmox-dev:/var/backup-relay/`. Same failure domain as
   TrueNAS NFS guest roots; a true off-site target is a separate decision.
4. Drop rpi4 from Prometheus scrapes, alert exclusions, and smokeping.
5. Supersedes [2026-08-31-rpi4-native-build.md](2026-08-31-rpi4-native-build.md).

### Consequences

* Good, because the flake and CI no longer carry a dead aarch64 path
* Bad, because backups and guest roots share the Proxmox/TrueNAS domain
* Bad, because restoring an aarch64 host later needs a new ADR and input

## Validation

`make check-inventory` lists three NixOS hosts. `nix flake check` has no
`aarch64-linux` deploy checks. Scrapes and `host=` CI reject `rpi4`.

## More Information

[deployments.md](../deployments.md),
[proxmox-dev-debian.md](../services/proxmox-dev-debian.md),
[restore-postgres.md](../runbooks/restore-postgres.md).
