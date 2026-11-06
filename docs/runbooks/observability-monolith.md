# Runbook: observability monolith cutover (historical)

**Status:** complete (2026-09-07). Do not re-run. This page records what
the cutover was. Nothing on it applies to the running fleet.

On 2026-09-07 `proxmox-observability-2`, `proxmox-db-1`, and
`proxmox-db-2` were collapsed onto one VM, `proxmox-observability`. VMs
104, 107, and 108 were destroyed. Why:
[observability monolith](../adr/2026-09-07-observability-monolith.md).

The monolith later became the Debian guest `proxmox-observability-debian`.
Prometheus and Loki keep 62 days on local disk, and Garage, Mimir, and
the Garage-backed Attic bucket are gone
([2026-11-04-local-metrics-and-logs.md](../adr/2026-11-04-local-metrics-and-logs.md),
[2026-11-06-decommission-garage.md](../adr/2026-11-06-decommission-garage.md)).

Operate the current guest from
[proxmox-observability-debian.md](../services/proxmox-observability-debian.md).
Hypervisor guests: [proxmox-host.md](../services/proxmox-host.md).
