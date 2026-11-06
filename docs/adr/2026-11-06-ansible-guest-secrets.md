---
status: accepted
date: 2026-11-06
---

# Ansible guest secrets use inventory paths and alex-only recipients

## Context and Problem Statement

Debian Proxmox guests are applied with `fleet.debian_guest` Ansible, which
decrypts a sops file on the controller once per play. Those files still
lived under destroyed NixOS hostnames (`secrets/proxmox-applications-1/`,
`…-2/`, `secrets/proxmox-observability/`) and were encrypted to dead guest
age keys. How should Ansible-managed guest secrets be laid out and
recipients chosen, relative to NixOS sops-nix hosts?

## Decision Drivers

* Operators should edit secrets under the live MagicDNS / inventory name.
* Controllers decrypt; guests never need a sops age private key for apply.
* Destroyed NixOS age keys must not stay as recipients.
* NixOS hosts keep alex + host age for sops-nix at boot.

## Considered Options

* Keep legacy NixOS dirnames and dual recipients forever
* Rename to inventory paths; encrypt Ansible guests to alex only
* Put all secrets in one shared file

## Decision Outcome

Chosen option: "Rename to inventory paths; encrypt Ansible guests to alex
only", because the controller is the only decryptor for Ansible applies
and inventory names match what operators already SSH to.

Paths:

* `secrets/proxmox-applications-debian/`
* `secrets/proxmox-gitlab-debian/`
* `secrets/proxmox-observability-debian/`
* Builder stays `secrets/proxmox-dev/` (MagicDNS deploy name); recipients
  remain alex + the builder age key.

Router stays `secrets/router/` with alex + `proxmox-dev-debian` SSH age.
NixOS hosts unchanged (`secrets/<nixosHostname>/` with alex + host age).

`debian_guest_secrets_file` in each guest's host_vars points at the new
path. CI checks required key *names* without decrypting
(`scripts/check-secrets-keys.py`).

### Consequences

* Good, because dead hostnames and dead age keys leave the secrets tree
* Good, because a stolen destroyed-guest key cannot read Ansible secrets
* Bad, because only alex can decrypt Ansible guest files (no on-host
  emergency decrypt without the operator key)
* Neutral, because leftover unused keys in a file (e.g. old Garage S3) are
  allowed; required-key CI fails only on gaps

## Validation

* `.sops.yaml` creation rules for the three Debian paths list alex only
* `make check-secrets-keys` green in GitLab and GitHub CI
* `make edit-secrets HOST=proxmox-applications-debian` (and siblings) works

## Pros and Cons of the Options

### Keep legacy NixOS dirnames

* Good, because no rekey
* Bad, because docs and inventory lie about who owns the file

### Rename + alex-only (chosen)

* Good, because paths match inventory and recipients match who decrypts
* Bad, because one-time rekey and doc sweep

### One shared file

* Bad, because blast radius and inventory-secrets rule forbid it

## More Information

[docs/secrets.md](../secrets.md),
[inventory-secrets.mdc](../../.cursor/rules/inventory-secrets.mdc),
[proxmox-applications-debian.md](../services/proxmox-applications-debian.md).
