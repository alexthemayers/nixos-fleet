---
status: accepted
date: 2026-08-29
---

# Inventory duplication plus check-inventory

## Context and Problem Statement

Make cannot import Nix, and Nix should not parse the Makefile. Host lists
lived in both and drifted (`make reboot-all` once skipped live hosts).

## Decision Outcome

Keep two lists: `Makefile` `PROD_HOSTS` and
`config/fleet-inventory.nix`. `scripts/check-inventory.sh` / `make check-inventory`
fails CI when they disagree.

### Consequences

Adding a host means both files, plus `secrets/<host>/secrets.yaml`, a
`nixosConfigurations` entry, and `ssh/fleet_known_hosts`. Run
`make check-inventory` locally; GitLab runs it in `test` without `ATTIC_TOKEN`.
