---
status: accepted
date: 2026-08-31
---

# Proxmox hypervisor is Ansible, vault stays local

## Context and Problem Statement

The fleet VMs are NixOS. The hypervisor they run on is Proxmox VE (Debian),
so it cannot be a `nixosConfiguration`. Host identity, SR-IOV, iGPU
passthrough, and pmxcfs files still need to live next to the flake.

Ansible vault is a different secret store from sops-nix. Putting the vault
password in git would copy a pattern the Nix side already rejected.

## Decision Outcome

Manage `proxmox` from [`ansible/`](../../ansible/) (`make deploy-proxmox-host`).
Do not add a NixOS config for the hypervisor.

Keep `group_vars/all/vault.yml` encrypted in git. Keep
`ansible/.vault_pass.txt` on the operator machine only (gitignored). Do not
fold Ansible vault into sops-nix.

### Consequences

Nix deploys do not configure the hypervisor. A flake-only clone still needs
the vault password out of band to decrypt Keycloak's PVE client key.
Operators create `ansible/.vault_pass.txt` before `ansible-playbook`.
