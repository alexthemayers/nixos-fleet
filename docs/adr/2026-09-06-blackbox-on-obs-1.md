---
status: accepted
date: 2026-09-06
---

# Blackbox prober lives on proxmox-observability

## Context and Problem Statement

The only blackbox exporter ran on `rpi4`. Prometheus relabeled every
`blackbox_http` target to `rpi4:9115`. `TargetDown` already ignored
`instance=~"rpi4.*"`, but blackbox sets `instance` to the probed URL, so a
down Pi produced fifteen critical `TargetDown` pages and no `EndpointDown`
(`probe_success` disappears when the scrape fails).

## Decision Outcome

Run `services/blackbox-exporter.nix` on `proxmox-observability`. Probe
scrapes go to `proxmox-observability:9115`. A separate `blackbox` job
scrapes the exporter process itself. `rpi4` masks the old unit.

`TargetDown` ignores `job="blackbox_http"`. Site reachability is
`EndpointDown` on `probe_success`.

### Consequences

Synthetic monitoring shares the obs-1 SPOF with Grafana/Mimir/ntfy. The Pi
staying down no longer pages every public vhost. The blackbox token is now
in `secrets/proxmox-observability/` as well as on `xcloud-caddy`.
