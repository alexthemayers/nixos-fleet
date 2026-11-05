# Deployments

This document describes how the `nixos-fleet` configuration is verified and
deployed to target hosts.

## Deployment Architecture

Production activation builds on the native builder and `nix copy`s the
closure with `deploy-rs`, then `switch-to-configuration`. Hosts substitute
from `cache.nixos.org`. Attic is removed
([adr/2026-11-03-decommission-attic.md](adr/2026-11-03-decommission-attic.md)).

GitLab CI does not build or deploy. It only runs the lint gate. The
operator activates hosts from `proxmox-dev` / `rpi4`
([adr/2026-11-05-ci-lint-only.md](adr/2026-11-05-ci-lint-only.md)).

```mermaid
graph TD
    GitLab[GitLab Repository] -->|Push| CI[GitLab CI]
    CI -->|test| Gate[lint fmt inventory ansible-lint]
    Op[Operator on proxmox-dev] -->|deploy-host.sh| Host[NixOS host]
    OpPi[Operator via run-on-rpi4.sh] -->|deploy-host.sh rpi4| Pi[rpi4]
```

## Operator commands

```bash
make lint
make fmt-check
make check-inventory
make ansible-lint                                # ansible/ + fleet.debian_guest
make changed-hosts                               # toplevels that differ from BEFORE (default origin/main)
make deploy-host HOST=xcloud-caddy               # build + nix copy + switch (on proxmox-dev)
make deploy-rpi                                  # same for rpi4 on the Pi (scripts/run-on-rpi4.sh)
make deploy-proxmox-host                         # Ansible: Proxmox VE hypervisor (not NixOS)
make deploy                                      # production fleet including gaming; rpi4 via run-on-rpi4.sh
make deploy-gaming                               # same path, gaming only
make deploy-rs                                   # alias for make deploy
make bench-jellyfin-io                           # 4K Jellyfin I/O bench on apps-1
make jellyfin-library-audit                      # read-only NFO / path audit on apps-1
make router-status                               # log in to the LAN router from proxmox-dev
make reboot-router                               # reboot it on request (`ROUTER_ARGS=--dry-run|--force`)
```

Garage deploys on `proxmox-observability` first:
[runbooks/observability-monolith.md](runbooks/observability-monolith.md).

## deploy-rs Configuration

Targets are defined inside the `deploy.nodes` attribute in
[flake.nix](../flake.nix).

Nodes are constructed by a `mkNode` helper so these settings are declared
once rather than repeated per host:

- `hostname`: The MagicDNS Tailscale host name
- `sshUser`: `root`
- `sshOpts`: ControlMaster multiplexing plus `IdentitiesOnly` and the repo
  `ssh/fleet_known_hosts`
- `path`: The compiled system profile from `nixosConfigurations.<hostname>`
- `magicRollback`: `true` by default
- `remoteBuild`: `true` by default; hosts that set `remoteBuild = false`
  still compile on the builder when using `deploy-host.sh`

Production rpi4 activation is
[`scripts/run-on-rpi4.sh`](../scripts/run-on-rpi4.sh), not qemu on
`proxmox-dev`.

## CI/CD Pipeline

The GitLab CI configuration is defined in
[.gitlab-ci.yml](../.gitlab-ci.yml). GitHub
[`.github/workflows/lint.yml`](../.github/workflows/lint.yml) mirrors the
same gate. GitLab is CI of record
([adr/2026-11-05-ci-lint-only.md](adr/2026-11-05-ci-lint-only.md)).

### Test job

One job, always. `resource_group: proxmox-dev-nix` so it does not overlap
other Nix evals on the 12 GiB builder:

- [`scripts/lint.sh`](../scripts/lint.sh) (`nix flake check --all-systems --no-build`)
- `make fmt-check` (`nix fmt -- --ci`)
- [`scripts/check-inventory.sh`](../scripts/check-inventory.sh)
- [`scripts/ansible-lint.sh`](../scripts/ansible-lint.sh) (both Ansible trees)

No select stage, no child pipeline, no deploy jobs. `SSH_PRIVATE_KEY` is
not used by CI.

## Proxmox hypervisor (Ansible)

The VE host is not a flake target. Apply it with `make deploy-proxmox-host`
from [`ansible/`](../ansible/). See
[services/proxmox-host.md](services/proxmox-host.md) and
[adr/2026-08-31-proxmox-ansible.md](adr/2026-08-31-proxmox-ansible.md).
Lint it with `make ansible-lint` (also covers `fleet.debian_guest`).

## Operator machine

Edits land on the Darwin checkout. **x86_64 deploys run on
`root@proxmox-dev`.** aarch64 runs on `root@rpi4` via
[`scripts/run-on-rpi4.sh`](../scripts/run-on-rpi4.sh). Do not `make deploy`
from the laptop store or from `gaming`.

```bash
rsync -az --delete --exclude='.git/' --exclude='result' --exclude='.direnv/' \
  /Users/alex/code/nixos-fleet/ root@proxmox-dev:/root/nixos-fleet-deploy/
ssh -A root@proxmox-dev 'bash -s' << 'EOF'
set -euo pipefail
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
cd /root/nixos-fleet-deploy
./scripts/deploy-host.sh <host>
EOF
```

`proxmox-dev` has no root deploy key. `ssh -A` forwards the operator agent
so `nix copy` and `switch-to-configuration` can hop to the target. Plain
`ssh` fails with `Permission denied (publickey)`.

rpi4 (native aarch64; do not build this host on proxmox-dev):

```bash
./scripts/run-on-rpi4.sh ./scripts/deploy-host.sh rpi4
```

`--exclude='.git/'` means the copy is a path flake: every file on disk is
visible (including untracked). A `nix` eval **in this git checkout** only
sees tracked files — `git add` new Nix/Go/Python that a module references
or lint fails.

## Local vs GitLab

| | Local | GitLab |
|---|---|---|
| Nix | already installed on proxmox-dev / rpi4 | `nixos/nix` image + `.#ci-tools` |
| SSH | operator keys + `ssh/fleet_known_hosts` | not used (no deploy jobs) |
| Gate | `make lint fmt-check check-inventory ansible-lint` | same four targets in `test` |
| Deploy | `deploy-host.sh` (x86); `run-on-rpi4.sh` (rpi4) | none |

A green pipeline is not a license to deploy. GitHub Actions mirrors the
gate and has no tailnet.

## Scripts

| Script | Make target | Notes |
|---|---|---|
| [scripts/lint.sh](../scripts/lint.sh) | `make lint` | `flake check --all-systems --no-build` |
| [scripts/ansible-lint.sh](../scripts/ansible-lint.sh) | `make ansible-lint` | both Ansible trees; Galaxy deps; offline |
| [scripts/check-inventory.sh](../scripts/check-inventory.sh) | `make check-inventory` | needs `python3` |
| [scripts/check-secrets.sh](../scripts/check-secrets.sh) | `make check-secrets` | age key; **not CI** |
| [scripts/check-mimir-rules.sh](../scripts/check-mimir-rules.sh) | `make check-mimir-rules` | builds rules; **not CI** |
| [scripts/changed-hosts.sh](../scripts/changed-hosts.sh) | `make changed-hosts` | toplevel outPath vs `BEFORE` (default `origin/main`); `--all` |
| [scripts/deploy-host.sh](../scripts/deploy-host.sh) | `make deploy-host HOST=` | deploy-rs from builder store; skip switch if toplevel matches |
| [scripts/run-on-rpi4.sh](../scripts/run-on-rpi4.sh) | `make deploy-rpi` | copy checkout to the Pi; run deploy there |
| [scripts/nix-develop.sh](../scripts/nix-develop.sh) | | wrapper around `nix develop` |
| [scripts/update-known-hosts.sh](../scripts/update-known-hosts.sh) | `make update-known-hosts` | from a trusted workstation `known_hosts` |
| [scripts/run-router-reboot.sh](../scripts/run-router-reboot.sh) | `make router-status`, `make reboot-router` | [runbook](runbooks/router-reboot.md) |
| [scripts/jellyfin-library-audit.sh](../scripts/jellyfin-library-audit.sh) | `make jellyfin-library-audit` | read-only; SSH to apps-1 |

`make edit-secrets HOST=` / `make updatekeys` for sops. Ansible
(`make deploy-proxmox-host`) is not Nix; see
[services/proxmox-host.md](services/proxmox-host.md).

## Rollback

Every activation leaves a NixOS generation on the host. To walk one back,
or to recover a host that stopped answering SSH, see
[runbooks/rollback.md](runbooks/rollback.md). `make reboot-all` iterates
`PROD_HOSTS` and is a reboot, not a rollback.
