# ADR: iperf3 throughput mesh is on for every fleet host

**Status:** accepted (2026-09-06)

## Context

`fleet.networkTesting.enable` defaulted to false after the full-mesh
coordinator was judged a permanent tax on the 1 GiB Postgres hub and the
Pi. The `TailscaleNodeThroughput*` alerts kept watching
`node_network_throughput_iperf3_*` and stayed silent: last-run timestamps
were days old, gated by a 2h freshness check.

## Decision

`config/observability.nix` sets `fleet.networkTesting.enable = true` on
every host that imports it (the whole NixOS fleet). WAN pairs stay capped
at 120 Mbps.

## Consequences

The coordinator writes textfiles again, so the throughput alerts can fire.
xcloud-postgres and rpi4 spend a 2s iperf3 slot on their turn. Turn the
option off on a host only while investigating a load problem on that box.
