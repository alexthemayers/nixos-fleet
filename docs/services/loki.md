# Loki Log Aggregation Service Configuration

This document describes the **Grafana Loki** deploy in `nixos-fleet`.

## Overview

Loki runs on **`proxmox-observability`**. Clients (Alloy, Grafana) talk to it
at `proxmox-observability:3100` (Grafana on loopback). There is no Pi member: it is not in
`join_members`. A leftover rpi4 Loki (old generation, `Restart=always`) will
rejoin gossip and flood `/memberlist` with `loki-v4-rpi4-*` names. Stop that
unit **before** restarting obs Loki; then:

```bash
curl -sS http://127.0.0.1:3100/memberlist | grep -E 'Members:|loki-v4-'
# Members: 1, name loki-v4-proxmox-observability-* only
curl -sf http://127.0.0.1:3100/ready
```

`auth_enabled = false`. Loki's default is multi-tenant (`true`); Grafana's provisioned datasource and Alloy's
`loki.write` do not set `X-Scope-OrgID`, so queries and pushes fail with 401 `no org id`. This matches Mimir
(`multitenancy_enabled = false`). Tailscale is the perimeter.

## Networking and ports

Allowed on `tailscale0` only:

- **`3100`**: HTTP (push, query, `/ready`).
- **`9095`**: gRPC.
- **`7946`**: memberlist gossip (TCP/UDP).

## Secrets

- **`loki/s3_access_key`** and **`loki/s3_secret_key`**: Garage credentials for the `loki` bucket.

Rendered into `loki.env` (sops template) and loaded as `EnvironmentFile`.

## Storage

Chunks and the TSDB index go to Garage bucket `loki` via
`proxmox-observability:3902` (schema `v13`, 31 day retention). Garage
itself is RF=1 on obs-1.

## Clustering

Memberlist needs the host's tailscale0 IPv4, which is not known at build time. A oneshot `loki-cluster-env.service`
writes `/run/loki-cluster.env` (`LOKI_CLUSTER_IP`, join members) **before** `loki.service` starts. systemd loads
`EnvironmentFile` before `ExecStartPre`, so putting that path only in `ExecStartPre` fails the unit with `resources`
and the pre script never runs. Alertmanager uses the same oneshot pattern.

The query frontend does **not** inherit `common.ring.instance_addr`. Without
`frontend.instance_interface_names = [ "tailscale0" ]` (and `frontend.address`)
it advertises the LAN NIC. Queriers then health-check `192.168.3.x:9095`, which
the firewall does not allow, and Grafana label/Explore queries hang.

`replication_factor = 1` on the ingest ring: there is one ingester. Durability
is Garage, not a second in-memory replica.

`MemoryMax = 768M` so Loki cannot OOM the 8 GiB VM that also runs Grafana,
Prometheus, Alloy, Mimir, and Garage
([memory.md](../memory.md)).

`stopIfChanged` / `restartIfChanged` are false so a NixOS switch that restarts `tailscaled` does not take Loki down
with the activation.

## Caddy

Internal Caddy listens on `:3100` (any Host) and reverse-proxies obs-1 with
`/ready` health checks. When that backend fails, the LB returns 5xx, not an
empty 200.

## Alerting

Rules live in the `loki` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix).
Dashboard: `fleet-loki`.

| Alert | Catches |
|---|---|
| `LokiTargetDown` | scrape of `:3100` failed |
| `LokiRingWrongSize` | ACTIVE members ≠ 1 on ingester/distributor/scheduler/compactor |
| `LokiRingMemberUnhealthy` | a ring member is `UNHEALTHY` |
| `LokiRequestErrors` | HTTP 5xx rate above 5% on a route |
| `LokiS3Errors` | Garage 5xx rate above 5%, or more than 0.5 5xx/s |
| `LokiCompactorHasNotRun` | no successful compact-tables in 2h |
| `LokiIngesterFlushFailures` | chunk flushes failing |
| `LokiWALDiskFull` | WAL writes failing on a full disk |
| `LokiClientDrops` | Alloy dropped entries (`loki_write_dropped_entries_total`) |
| `LokiPanic` | `loki_panic_total` increased |

`LokiRingWrongSize` is the leftover-member check: a retired obs-2 or rpi4
Loki raises ACTIVE above 1. Compactor last-success uses `max()` because
only the elected member exports a non-zero timestamp.
