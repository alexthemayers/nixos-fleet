---
status: accepted
date: 2026-09-08
---

# Alloy on xcloud-postgres is MemoryMax 384M

## Context and Problem Statement

`xcloud-postgres` overrides the fleet Alloy cgroup
([2026-09-04-xcloud-postgres-1g](2026-09-04-xcloud-postgres-1g.md)) so a
Loki outage cannot grow the forwarder until the 1 GiB hub OOMs. The live
knobs were `MemoryHigh=112M`, `MemoryMax=160M`, `GOMEMLIMIT=96MiB`.

After the 2026-09-08 fleet reboot, those caps were the working set: the
cgroup sat on `memory.high` (~10.7 million trips in 7.5h), swapped ~90
MiB of Alloy, and systemd accounted ~14 TiB of disk reads. `vmstat`
showed ~62% iowait and 0% idle on the single vCPU. Postgres and
PgBouncer stayed up; checkpoints took ~50s to write a few megabytes.
Alloy `:12345/metrics` timed out (`up{job="alloy"}=0`). Journal was ~3k
lines/min, mostly kernel audit, which Alloy tails.

The live VM is still 1.9 GiB (`MemAvailable` ~1 GiB). How large should
Alloy be on this host?

## Decision Drivers

* Postgres latency on this SPOF is worse than missing some logs.
* Fleet default `MemoryMax=512M` is for 4 GiB obs VMs.
* Journal is capped at `SystemMaxUse=64M`; leftover Loki WAL can be
  ~120 MiB on disk.
* Do not shrink the provider VM to 1 GiB while Alloy needs this room.

## Considered Options

* Raise to `MemoryHigh=320M`, `MemoryMax=384M`, `GOMEMLIMIT=192MiB`
* Use the fleet default `384M` / `512M`
* Keep `160M` and drop journal or audit instead
* Disable Alloy on this host

## Decision Outcome

Chosen option: "`MemoryHigh=320M`, `MemoryMax=384M`,
`GOMEMLIMIT=192MiB`", because that fits journal + a Go heap + leftover
WAL without using the obs-VM 512M cap. Host override stays in
[hosts/xcloud-postgres/configuration.nix](../../hosts/xcloud-postgres/configuration.nix).

Do not set the fleet 512M default on this hub. Do not shrink the cloud
VM to 1 GiB until Alloy's working set is cut another way (audit volume
or journal shipping). Postgres knobs in the 1 GiB ADR are unchanged.

### Consequences

* Good, because reclaim no longer saturates the disk as the normal
  path.
* Bad, because Alloy can now hold ~320–384 MiB on a hub still aimed at
  1 GiB, so shrinking the provider VM stays blocked.
* Bad, because audit still floods the journal; this only gives Alloy
  room to tail it.

## Validation

After switch, `curl -m 3 http://127.0.0.1:12345/metrics` succeeds,
`memory.events` `high` stops climbing at hundreds per second, and
`vmstat` idle is not 0. Alert: `AlloyTargetDown`
(`up{job="alloy"} == 0`, excluding `gaming` / `rpi4` / `m3pro`).
Dashboard: `fleet-alloy`.

## More Information

[xcloud-postgres 1 GiB](2026-09-04-xcloud-postgres-1g.md),
[memory.md](../memory.md), [monitoring.md](../monitoring.md).
