# Loki Log Aggregation Service Configuration

This document describes the **Grafana Loki** deploy in `nixos-fleet`.

## Overview

Loki runs on **`proxmox-observability-1`** and **`proxmox-observability-2`**. Clients (Alloy, Grafana) talk to it through
`proxmox-lb:3100`. There is no Pi member: it left the ring and is not in `join_members`.

## Networking and ports

Allowed on `tailscale0` only:

- **`3100`**: HTTP (push, query, `/ready`).
- **`9095`**: gRPC.
- **`7946`**: memberlist gossip (TCP/UDP).

## Secrets

- **`loki/s3_access_key`** and **`loki/s3_secret_key`**: Garage credentials for the `loki` bucket.

Rendered into `loki.env` (sops template) and loaded as `EnvironmentFile`.

## Storage

Chunks and the TSDB index go to Garage bucket `loki` via `proxmox-lb:3902` (schema `v13`, 31 day retention). Garage
itself is RF=2 across db-1 and db-2.

## Clustering

Memberlist needs the host's tailscale0 IPv4, which is not known at build time. A oneshot `loki-cluster-env.service`
writes `/run/loki-cluster.env` (`LOKI_CLUSTER_IP`, join members) **before** `loki.service` starts. systemd loads
`EnvironmentFile` before `ExecStartPre`, so putting that path only in `ExecStartPre` fails the unit with `resources`
and the pre script never runs. Alertmanager uses the same oneshot pattern.

The query frontend does **not** inherit `common.ring.instance_addr`. Without
`frontend.instance_interface_names = [ "tailscale0" ]` (and `frontend.address`)
it advertises the LAN NIC. Queriers then health-check `192.168.3.x:9095`, which
the firewall does not allow, and Grafana label/Explore queries hang.

`replication_factor = 1` on the ingest ring: two ingesters with RF=2 required both to ack, so one obs node down stopped
all writes. Durability is Garage, not a second in-memory replica.

`MemoryMax = 768M` so Loki cannot OOM a 4–6 GiB VM that also runs Grafana, Prometheus, Alloy, and Mimir.

`stopIfChanged` / `restartIfChanged` are false so a NixOS switch that restarts `tailscaled` does not take Loki down
with the activation.

## Caddy

Internal Caddy listens on `:3100` (any Host) and reverse-proxies the two obs nodes with `/ready` health checks. When
both fail, the LB returns 5xx, not an empty 200.
