---
status: accepted
date: 2026-09-06
---

# Vaultwarden has no edge failover to rpi4

## Context and Problem Statement

Edge Caddy listed `rpi4:8222` as a second Vaultwarden upstream with
`lb_policy first`. The Pi is often down, so
`CaddyUpstreamUnhealthy` pages on `rpi4:8222` while `TargetDown` already
ignores that host. The replica and Syncthing copy still exist; only the
edge path was a monitored zombie.

## Decision Outcome

`vaultwarden.alexmayers.co.za` reverse-proxies `proxmox-lb:80` only, like
the other app vhosts.

### Consequences

A `proxmox-lb` outage takes Vaultwarden with every other public app.
`rpi4` remains the USB backup target and still runs Vaultwarden plus
Syncthing; it is not in the edge path.
