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
4. Live Garage and Mimir alert and dashboard content is gone: the
   `LokiS3Errors` rule and the `S3 5xx/s` panel in `fleet-loki` had no
   series (Loki uses `object_store: filesystem`). No scrape job names
   Garage or Mimir.
5. Supersedes
   [2026-09-07-garage-on-obs-1.md](2026-09-07-garage-on-obs-1.md),
   [2026-09-18-garage-iscsi.md](2026-09-18-garage-iscsi.md),
   [2026-09-05-garage-lmdb-migration.md](2026-09-05-garage-lmdb-migration.md),
   [2026-09-18-garage-blocks-loopback-ext4.md](2026-09-18-garage-blocks-loopback-ext4.md),
   [2026-09-05-mimir-series-headroom.md](2026-09-05-mimir-series-headroom.md),
   and
   [2026-09-05-mimir-delete-lost-blocks.md](2026-09-05-mimir-delete-lost-blocks.md).
   Those ADR files stay as history. The `prometheus.yml` cardinality drops
   stay because they shrink the 62-day TSDB.
6. Nothing in Nix, Ansible, or scripts reads the secret keys below
   (grepped; the files were not decrypted). The agent cannot edit sops
   YAML without the age key, so the operator removes them.

### Operator follow-ups

Remove the unused keys with `make edit-secrets HOST=<host>`, then
`make check-secrets`.

| Host file | Keys to delete |
|-----------|----------------|
| `secrets/proxmox-observability-debian/secrets.yaml` | `loki/s3_access_key`, `loki/s3_secret_key`, `mimir/s3_access_key`, `mimir/s3_secret_key`, `garage/rpc_secret`, `garage/admin_token` |
| `secrets/proxmox-dev/secrets.yaml` | `attic/env` (see [decommission-attic](2026-11-03-decommission-attic.md)) |

The Postgres `DROP DATABASE` and `DROP ROLE` statements for `attic` and
`coder` are in [decommission-attic](2026-11-03-decommission-attic.md) and
[decommission-coder](2026-11-06-decommission-coder.md).

When no one needs the old Garage blocks and chunks, on TrueNAS remove the
iSCSI target for `ssd/garage-iscsi`, then `zfs destroy ssd/garage-iscsi`.
Delete the "Do not `zfs destroy ssd/garage-iscsi`" lines in
`.cursor/rules/infrastructure.mdc` and this ADR's guard in the same
change. Destroying the zvol deletes the only copy of the pre-2026-11-04
metrics and logs.

### Consequences

* Good, because live docs match the running fleet
* Bad, because the unused zvol still occupies TrueNAS until cleaned up

## Validation

No `fleet/apps/garage.nix`. No Garage or Mimir scrape job or alert.
`rg -i 'garage|mimir' collections/.../observability/files/` finds no
live job. `infrastructure.mdc` still forbids destroying the zvol.

## More Information

[local-metrics-and-logs](2026-11-04-local-metrics-and-logs.md),
[proxmox-observability-debian.md](../services/proxmox-observability-debian.md).
