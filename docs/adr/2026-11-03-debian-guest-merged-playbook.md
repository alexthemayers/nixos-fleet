---
status: accepted
date: 2026-11-03
---

# Debian guests share one site.yml and inventory

## Context and Problem Statement

The `fleet.debian_guest` collection grew separate playbooks and inventories
for the applications guest (VM 109) and the GitLab guest (VM 110). How
should operators apply either guest without inventing a second entry
point or letting an unscoped run touch both?

## Decision Drivers

* One collection already owns both guests
  ([2026-11-01-debian-applications-guest](2026-11-01-debian-applications-guest.md),
  [2026-11-03-debian-gitlab-guest](2026-11-03-debian-gitlab-guest.md)).
* Accidental dual apply is expensive: SSO and GitLab share
  `xcloud-postgres`.
* VM create must install qemu-guest-agent without a second converge.

## Considered Options

* Keep `playbooks/gitlab.yml` and a second inventory
* One `site.yml` with static inventory, host_vars, and required `--limit`
* Fold guests into `ansible/proxmox.yml`

## Decision Outcome

Chosen option: "One `site.yml` with static inventory, host_vars, and
required `--limit`", because one tree and a hard `--limit` gate are
enough. `make deploy-debian-guest` and `make deploy-debian-gitlab` pass
`--limit`. The `vm` role creates with `import-from` plus a cicustom
vendor snippet that installs `qemu-guest-agent` on first boot.

### Consequences

* Good, because operators have one playbook and cannot run without
  naming a host.
* Bad, because GitLab apply and apps apply stay separate make targets;
  a full-fleet guest apply is deliberately refused.

## Validation

`site.yml` fails fast without `--limit`. `qm config` shows the vendor
snippet storage. Collection README documents the two make targets.

## More Information

Collection:
`collections/ansible_collections/fleet/debian_guest`. Related:
[2026-11-03-debian-guest-rootless-podman.md](2026-11-03-debian-guest-rootless-podman.md).
