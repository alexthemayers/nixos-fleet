---
status: accepted
date: 2026-09-08
---

# Journal shipping is Vector, not Alloy

## Context and Problem Statement

Every fleet host and the Proxmox hypervisor shipped systemd journals (and
postgres jsonlog on `xcloud-postgres`) to Loki with Grafana Alloy. Alloy's
Go heap plus journal tail made the 1 GiB hub cap a reclaim storm at 160M
and still needed 384M to scrape
([2026-09-08-xcloud-postgres-alloy-cap](2026-09-08-xcloud-postgres-alloy-cap.md)).
Uncapped Alloy peaked at ~2.2 GiB on the obs VM. Should the fleet keep
Alloy, shrink it further, or replace the forwarder?

## Decision Drivers

* Postgres latency on `xcloud-postgres` is worse than missing some logs.
* A Loki outage must delay journals, not OOM the box or drop the lines
  that explain the outage.
* Loki labels `job`, `host`, `service`, `syslog_id`, `syslog_facility`
  stay query-compatible.
* One forwarder on NixOS hosts and on the Debian hypervisor.

## Considered Options

* Keep Alloy with the 384M / 512M caps
* Keep Alloy and drop journal or audit on the postgres hub
* Replace Alloy with Vector (journald + file sources, Loki sink)

## Decision Outcome

Chosen option: "Replace Alloy with Vector", because Vector is a smaller
Rust working set, disk-buffers Loki pushes, and still tails journald and
postgres jsonlog.

Module: [config/observability.nix](../../config/observability.nix).
Hypervisor: [ansible/roles/vector](../../ansible/roles/vector). Metrics
on `:9598`, job `vector`. Disk buffer is 256 MiB (`when_full = block`) so
a Loki outage stalls the journal cursor; journald retains until
`SystemMaxUse`. Fleet cgroup is `MemoryHigh=192M` / `MemoryMax=256M`.
`xcloud-postgres` overrides to `96M` / `128M` (no `GOMEMLIMIT`).

Do not re-enable Alloy. Do not scrape `:12345`.

This supersedes
[2026-09-08-xcloud-postgres-alloy-cap](2026-09-08-xcloud-postgres-alloy-cap.md).

### Consequences

* Good, because the postgres hub no longer needs a 320–384 MiB Go heap
  to tail the journal.
* Good, because a Loki outage is a Vector disk buffer plus journald, not
  an unbounded Alloy heap.
* Bad, because Alloy WAL / `loki_write_*` series end at switch; new
  alerts use `vector_component_*`.
* Bad, because first-start Vector may catch up the current journal (no
  12h `max_age` window).

## Validation

After switch, `curl -m 3 http://127.0.0.1:9598/metrics` succeeds,
`systemctl is-active vector` is `active`, and Alloy is gone
(`systemctl status alloy` is missing or inactive). Alert:
`VectorTargetDown` (`up{job="vector"} == 0`, excluding `gaming` / `rpi4`
/ `m3pro`). Dashboard: `fleet-vector`. Hypervisor: `make
deploy-proxmox-host`.

## Pros and Cons of the Options

### Keep Alloy with the 384M / 512M caps

* Good, because no client or label change.
* Bad, because the 1 GiB hub still cannot shrink while Alloy needs that
  room, and obs VMs still pay a Go heap.

### Keep Alloy and drop journal or audit on the postgres hub

* Good, because RAM falls without a new daemon.
* Bad, because the audit flood is then invisible in Loki, which is the
  signal we kept Alloy for.

### Replace Alloy with Vector

* Good, because RSS is typically tens of MiB plus a size-capped disk
  buffer.
* Good, because NixOS has `services.vector` and Debian has
  `apt.vector.dev`.
* Bad, because scrape, alerts, and the hypervisor role all move in one
  change.

## More Information

[monitoring.md](../monitoring.md), [memory.md](../memory.md),
[xcloud-postgres 1 GiB](2026-09-04-xcloud-postgres-1g.md).
