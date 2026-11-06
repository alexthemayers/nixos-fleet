# Garage

Garage is **not running** on the Debian observability guest. The zvol
`ssd/garage-iscsi` still holds a copy of old Mimir blocks and Loki chunks;
VM 103 was destroyed on 2026-11-04, so nothing mounts it.
**Do not `zfs destroy ssd/garage-iscsi`.**

Historical decisions (do not treat as live runbooks):

* Placement: [2026-09-07-garage-on-obs-1.md](../adr/2026-09-07-garage-on-obs-1.md)
* LMDB: [2026-09-05-garage-lmdb-migration.md](../adr/2026-09-05-garage-lmdb-migration.md)
* iSCSI: [2026-09-18-garage-iscsi.md](../adr/2026-09-18-garage-iscsi.md)

Operator landmines remain in
[infrastructure.mdc](../../.cursor/rules/infrastructure.mdc) and
[runbooks/garage-iscsi.md](../runbooks/garage-iscsi.md) /
[garage-metadata-resync.md](../runbooks/garage-metadata-resync.md) for
the day Garage returns. Live logs/metrics are local Prometheus + Loki on
[proxmox-observability-debian.md](proxmox-observability-debian.md).
