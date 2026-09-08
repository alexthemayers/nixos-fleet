---
status: accepted
date: 2026-09-07
---

# No internal load balancer; edge and clients talk to the serving VM

## Context and Problem Statement

`proxmox-lb` was a second Caddy hop: the edge forwarded almost every vhost to
`proxmox-lb:80`, and east-west clients used `proxmox-lb:3902` / `:3100` /
`:9009` / `:9093` / `:8080`. After collapsing observability and Garage onto
one VM, that hop load-balanced nothing except Keycloak and Vikunja on
apps-1/apps-2. Should the fleet keep the extra VM, keep the pairs without an
LB, or send traffic straight to the serving instance?

## Decision Drivers

* `proxmox-lb` is already a SPOF
  ([four hubs](2026-08-29-four-hubs.md)); a pair behind it does not survive
  the LB.
* Keycloak JGroups and a second Vikunja on the same motherboard do not buy
  a failure domain
  ([fleet simplification plan](../fleet-simplification-plan.md) Phases 4–5).
* Caddy on `proxmox-lb:8080` truncates multi-chunk Attic NARs; deploys
  already bypass it.
* Moving a service between VMs becomes an `xcloud-caddy` deploy. With one
  hypervisor that is the correct trade.

## Considered Options

* Keep `proxmox-lb` as a Host router in front of single backends
* Point the edge at backends; keep Keycloak and Vikunja clustered
* Point the edge and every internal client at the serving VM; one Keycloak
  and one Vikunja on `proxmox-applications-1`

## Decision Outcome

Chosen option: "Point the edge and every internal client at the serving VM;
one Keycloak and one Vikunja on `proxmox-applications-1`", because the LB
no longer balances a replica pair that shares power, CPU, and NFS.

`xcloud-caddy` reverse-proxies each vhost to the process port on the
backend host and proxies UDP 27960/30000 to apps-1. Garage S3, Loki,
Mimir, Alertmanager, and Vector use `proxmox-observability` directly. Grafana
datasources use loopback on that same VM. Attic substituters stay
`http://proxmox-dev:8080/attic`. Attic's S3 endpoint is
`http://proxmox-observability:3902`.

`proxmox-lb` is removed from inventory. VM 105 was destroyed on
2026-09-07. Runbook:
[retire-proxmox-lb.md](../runbooks/retire-proxmox-lb.md).

Supersedes [four hubs](2026-08-29-four-hubs.md) (three hubs remain:
`xcloud-caddy`, `xcloud-postgres`, `truenas-scale`) and
[Garage S3 via LB](2026-08-30-garage-s3-lb.md) (there is one Garage node;
the pin is the cluster). Amends the S3 client sentence in
[Garage on obs-1](2026-09-07-garage-on-obs-1.md).

### Consequences

* Good, because every public request and every S3/Loki/Mimir call has one
  fewer unreplicated hop.
* Good, because Keycloak is one JVM and Vikunja is one process; no
  JGroups or `co-routed-peers`.
* Bad, because moving a service between VMs is an edge Caddy deploy.
* Bad, because a down apps-1 takes Keycloak and Vikunja with Jellyfin.

## Validation

`make check-inventory` has eight NixOS hosts and no `proxmox-lb`. Edge
vhosts return 200 against the backend hosts. `job=caddy` scrapes
`xcloud-caddy:2019` only. `job=keycloak` and `job=vikunja` scrape apps-1
only. No `KeycloakClusterWrongSize` rule.

## More Information

[caddy.md](../services/caddy.md), [keycloak.md](../services/keycloak.md),
[vikunja.md](../services/vikunja.md),
[garage.md](../services/garage.md).
