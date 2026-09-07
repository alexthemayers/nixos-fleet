---
status: accepted
date: 2026-09-07
---

# Observability is one VM, not a pair

## Context and Problem Statement

`proxmox-observability` and `proxmox-observability-2` each ran Grafana,
Prometheus (agent), Loki, Mimir, ntfy, and Alertmanager on the same
hypervisor, with memberlist gossip, an Alertmanager cluster, and a duplicate
scrape. Loki and Mimir were already `replication_factor = 1`. Paging already
depended on obs-1
([ntfy single writer](2026-09-04-ntfy-json-priority-single-writer.md)).
Should the fleet keep the second observability VM?

## Decision Drivers

* Both VMs share one CPU, one PSU, one NFS server, and one NVMe.
* Two 4 GiB VMs were tighter than one 8 GiB VM (Grafana and Prometheus
  already above 75% of cap).
* Duplicate scrape and memberlist cost RAM and produced false "cluster"
  alerts.

## Considered Options

* Keep the two-VM pair
* One observability VM (`proxmox-observability`), drop obs-2
* Merge observability into `proxmox-dev` or an apps VM

## Decision Outcome

Chosen option: "One observability VM (`proxmox-observability`)", because
the pair did not survive the failure domain that actually fails, and one
writer is the shape the stack already had for paging and for S3
(`replication_factor = 1`).

The remaining guest is named `proxmox-observability` (no numeric suffix).
`proxmox-observability-2` is removed from inventory (VM 104 destroyed
2026-09-07). Internal Caddy has a
single backend for Grafana, ntfy, Loki, Mimir, and Alertmanager. Memberlist
`join_members` is that host only. Alertmanager has no `clusterPeers`. The
obs half of `co-routed-peers` is deleted.

Garage also runs on this VM
([garage on obs-1](2026-09-07-garage-on-obs-1.md)). Raise the guest to 8 GiB
and 4 vCPU before switching that generation.

### Consequences

* Good, because Grafana and Prometheus get the RAM they were pressing
  against, and scrape/cardinality is no longer doubled.
* Good, because `LokiRingWrongSize` and Alertmanager split-brain stop being
  structurally false.
* Bad, because a reboot of obs-1 is a metrics, logs, paging, and S3 outage
  until it is back. That is the same class as the four hubs.
* Bad, because ntfy SQLite lives on one disk; there is no second daemon to
  fail over to.

## Validation

`make check-inventory` has no `proxmox-observability-2`. Prometheus scrape
jobs for grafana/loki/mimir/ntfy/prometheus list only obs-1.
`LokiRingWrongSize` wants 1 ACTIVE member.

## More Information

Runbook: [observability-monolith.md](../runbooks/observability-monolith.md).
Blackbox was already obs-1 only
([blackbox on obs-1](2026-09-06-blackbox-on-obs-1.md)).
