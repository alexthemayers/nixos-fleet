---
status: accepted
date: 2026-09-01
---

# Desktops stay out of packet-loss alerts

## Context and Problem Statement

`TargetDown` already ignores `gaming`, `m3pro`, and `rpi4`. Smokeping still
pings them, so `TailscaleNodeHighPacketLoss` fired 100% loss to `gaming`
whenever the workstation was off (15h+ overnight). That is not a fleet
outage.

## Decision Outcome

`TailscaleNodeHighPacketLoss` and `TailscaleNodeHighLatency` use the same
`exported_host` exclusion as `TargetDown` (`rpi4|gaming|m3pro`). Smokeping
keeps probing; we just do not page.

### Consequences

A real tailnet problem that only affects the desktops will not page. Probe
the series in Grafana if that matters. Disk/CPU/memory alerts use the same
`m3pro|gaming` exclusion. Blackbox no longer runs on `rpi4`
([2026-09-06-blackbox-on-obs-1.md](2026-09-06-blackbox-on-obs-1.md)).
Backup rsync failures stay as rpi4 work.
