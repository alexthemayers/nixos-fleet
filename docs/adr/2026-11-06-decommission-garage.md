---
status: accepted
date: 2026-11-06
---

# Decommission Garage and Mimir S3

## Context and Problem Statement

Garage on the observability path and Mimir's S3 backend are not running.
Prometheus and Loki keep 62 days on local disk
([2026-11-04-local-metrics-and-logs.md](2026-11-04-local-metrics-and-logs.md)).
Live docs and rules still described Garage as if it were online.

## Decision Drivers

* Stop operator docs from pointing at missing runbooks and scrapes
* Keep the TrueNAS zvol until the operator deletes it on purpose

## Considered Options

* Leave Garage docs as "offline" stubs
* Remove live Garage/Mimir references; keep ADRs; leave the zvol
* Destroy the zvol in the same change

## Decision Outcome

Chosen option: "Remove live Garage/Mimir references; keep ADRs; leave the
zvol", because the processes are already gone and destroying storage is
operator work on TrueNAS.

1. Delete `fleet/apps/garage.nix`, Garage/Mimir service stubs, and Garage
   runbooks from live docs.
2. Do not scrape Garage. Do not alert on Garage S3.
3. **Do not `zfs destroy ssd/garage-iscsi`** until the operator removes
   the iSCSI target and zvol on TrueNAS.
4. Operator secret cleanup (when ready): Garage keys under
   `secrets/proxmox-observability-debian` and any leftover `mimir` /
   `loki` S3 ciphertext that nothing reads — `make edit-secrets HOST=…`.
5. Supersedes live use of
   [2026-09-07-garage-on-obs-1.md](2026-09-07-garage-on-obs-1.md),
   [2026-09-18-garage-iscsi.md](2026-09-18-garage-iscsi.md),
   [2026-09-05-garage-lmdb-migration.md](2026-09-05-garage-lmdb-migration.md),
   [2026-09-18-garage-blocks-loopback-ext4.md](2026-09-18-garage-blocks-loopback-ext4.md).
   Those ADR files stay as history.

### Consequences

* Good, because live docs match the running fleet
* Bad, because the unused zvol still occupies TrueNAS until cleaned up

## Validation

No `fleet/apps/garage.nix`. No Garage scrape job. `infrastructure.mdc`
still forbids destroying the zvol.

## More Information

[local-metrics-and-logs](2026-11-04-local-metrics-and-logs.md),
[proxmox-observability-debian.md](../services/proxmox-observability-debian.md).
