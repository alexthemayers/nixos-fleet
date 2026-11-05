---
status: accepted
date: 2026-11-04
---

# The builder moves to a Debian guest and keeps the name proxmox-dev

## Context and Problem Statement

`proxmox-dev` (VM 106) is the x86 builder, the GitLab runner, and the
landing zone for GitLab and Postgres backups. Coder also ran there.
How should that guest move to Debian without a second runner
registration or a new backup target?

## Decision Drivers

* `ssh root@proxmox-dev` and `backup-relay@proxmox-dev` are the
  addresses deploys and backup jobs already use.
* The runner is already registered as `proxmox-gaming-runner`.
* Coder is unused.
* One Nix eval needs most of a 12 GiB guest. Two evals OOM it.
* A CI container must not be able to read host secrets. Privileged
  mode stays off.

## Considered Options

* Rebuild Debian in place on VM 106
* A new MagicDNS name, as with the observability guest
* VM 112 in `fleet.debian_guest`, same Tailscale node, name stays
  `proxmox-dev`

## Decision Outcome

Chosen option: "VM 112 in `fleet.debian_guest`, same Tailscale node,
name stays `proxmox-dev`", because the name is the deploy target and
the backup target.

VM 112 is `proxmox-dev-debian`: Debian 13, 4 cores, 16 GiB, 200 GiB
qcow2 on `truenas-storage`, one X710 VF. Apply with
`make deploy-debian-dev`. The cutover flag copies Tailscale state, the
runner state, and `/var/backup-relay` off VM 106, which must be
stopped. The listen port stays 41649.

The runner is rootless Podman, docker executor, no privileged
containers. Concurrency stays 10 and the per-runner limit stays 4.
Each job container is 12 GiB, no swap, 3 CPUs. The Podman service is
capped at 14 GiB. Multi-user Nix is installed so x86 deploys still
build here. Coder is removed. GitLab backups are kept 14 days and
Postgres backups 30 days, on this VM, not on `rpi4`.

### Consequences

* Good, because backup jobs and `ssh -A root@proxmox-dev` do not change.
* Good, because one Nix job fits, and the containers together cannot
  take the whole guest.
* Bad, because VM 106 and VM 112 must not both run `tailscaled`.

## Validation

`tailscale status` on VM 112 reports hostname `proxmox-dev`.
`gitlab-runner verify` succeeds. A file can be written over SSH as
`backup-relay`. Node exporter on `proxmox-dev:9100` answers.

## More Information

[proxmox-dev-debian.md](../services/proxmox-dev-debian.md).
