# ADR: Desktops stay out of packet-loss alerts

**Status:** accepted (2026-09-01)

## Context

`TargetDown` already ignores `gaming`, `m3pro`, and `rpi4`. Smokeping still
pings them, so `TailscaleNodeHighPacketLoss` fired 100% loss to `gaming`
whenever the workstation was off (15h+ overnight). That is not a fleet
outage.

## Decision

`TailscaleNodeHighPacketLoss` and `TailscaleNodeHighLatency` use the same
`exported_host` exclusion as `TargetDown` (`rpi4|gaming|m3pro`). Smokeping
keeps probing; we just do not page.

## Consequences

A real tailnet problem that only affects the desktops will not page. Probe
the series in Grafana if that matters. `rpi4` blackbox `TargetDown` and
backup rsync failures stay as rpi4 work.
