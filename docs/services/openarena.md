# OpenArena

**Host:** `proxmox-applications-debian` · **Role:**
[`fleet.debian_guest` apps/openarena](../../collections/ansible_collections/fleet/debian_guest/roles/apps/tasks/openarena.yml)

## Overview

OpenArena is the UDP game server. There is one instance. It is not clustered
and it is not behind oauth2-proxy.

## Networking

- The daemon listens on UDP `27960` on `proxmox-applications-debian`.
- Only `tailscale0` allows `27960/udp` on the app host.
- Public players reach it through the edge Caddy layer-4 proxy
  (`xcloud-caddy` UDP `27960` → `proxmox-applications-debian`).
  That public UDP open on `xcloud-caddy` is intentional.

## Storage

`truenas-scale:/mnt/ssd/openarena` is mounted at `/mnt/nfs/openarena`, gated by
`fleet.waitForHost.openarena`.
