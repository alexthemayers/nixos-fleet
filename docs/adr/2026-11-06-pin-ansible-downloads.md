---
status: accepted
date: 2026-11-06
---

# Ansible downloads are checksum-pinned; collections are version-pinned

## Context and Problem Statement

The Ansible trees fetched vendor material without verifying it. The
GitLab Runner key was a `get_url` with no checksum. The Tailscale,
GitLab and Vector (Datadog) keys were passed to `deb822_repository` as
`signed_by: https://...`, so apt fetched a key on its own and nothing
pinned it. The Proxmox host downloaded four more keys unverified.
`requirements.yml` listed `ansible.posix` and `community.general` with no
version, and `scripts/ansible-lint.sh` reinstalls them with `--force`, so
the lint result could change without a commit. The two exporter tarballs
already carried a `sha256`; nothing required the rest to.

## Decision Drivers

* A compromised or swapped key URL must fail the deploy, not trust itself
* Lint and deploy must not change without a commit
* The rule has to be enforced by CI ([zero-debt](../../.cursor/rules/zero-debt.mdc))

## Considered Options

* Leave keys to apt and document the trust model
* Pin each vendor key by sha256, download it with `get_url`, and point
  `signed_by` at the file; pin Galaxy collections by version
* Vendor the keys into the repo

## Decision Outcome

Chosen option: "Pin each vendor key by sha256 ...", because it fails
closed, needs no key material in the repo, and uses the pattern the
exporter tarballs already follow.

1. Every `get_url` sets `checksum`. Guest keys use
   `debian_guest_*_key_sha256` in
   `collections/ansible_collections/fleet/debian_guest/inventory/group_vars/all.yml`.
   Hypervisor keys carry their hash inline in `ansible/roles/apt_repos`.
2. No `deb822_repository` / `apt_repository` `signed_by` is a URL, and
   `apt_key` is not used.
3. A hash proves the bytes did not change since the pin, not that the
   first bytes were genuine. Check the key's fingerprint against the
   vendor's published one when you first pin it or refresh it
   ([updates.md](../runbooks/updates.md)).
4. Both `requirements.yml` files pin `ansible.posix` and
   `community.general` to an exact version.
5. `scripts/check-ansible-downloads.py` (`make check-ansible-downloads`,
   in `make ci`) fails on any of the above, including a checksum variable
   that no defaults or vars file defines.

### Consequences

* Good, because a swapped or rotated key stops the deploy at the
  `get_url` task and lint no longer drifts
* Bad, because a legitimate vendor key rotation now fails the next deploy
  until someone verifies the new key and updates the hash
  ([updates.md](../runbooks/updates.md), "Refresh a pinned vendor key")
* Bad, because collection upgrades are now a deliberate commit

## Validation

`make check-ansible-downloads` and `make ansible-lint` pass. After the
next deploy, `apt update` on each guest and the hypervisor succeeds.
