# Loki Log Aggregation Service Configuration

This document describes the deployment and configuration details of the **Grafana Loki** service in the `nixos-fleet`
infrastructure.

## Overview

Loki is a horizontally scalable, multi-tenant log aggregation system. In this fleet, it is deployed in a clustered
configuration across the observability nodes, **`proxmox-observability-1`**, **`proxmox-observability-2`**, and the
backup node, **`rpi4`**.

## Networking and Ports

Loki exposes the following ports, allowed strictly on the Tailscale firewall:

- **`3100`**: HTTP port (scraped by Grafana).
- **`9095`**: gRPC interface.
- **`7946`**: Memberlist gossip port (TCP/UDP, used for cluster communication and ring state synchronization).

## Secrets Management

- **`loki/s3_access_key`** & **`loki/s3_secret_key`**: S3 API keys used to authenticate chunks storage write requests on
  Garage.

Secrets are rendered into `loki.env` and loaded as systemd service environment variables.

## Storage and Compactor

- **Storage Backend**: Log blocks (chunks) and indexes are stored in the replicated Garage S3 storage cluster bucket
  named `loki` on `proxmox-db:3902`.
- **Schema**: Uses `tsdb` for index and `s3` for logs object storage (configured schema `v13`).
- **Retention**: Compaction is enabled with a retention period of 31 days (`744h`). Files older than 31 days are deleted
  automatically from S3.

## Clustering and Gossip Resolution

Loki runs as a cluster using memberlist gossip. To prevent hardcoding IPs, a systemd launcher override retrieves the
local `tailscale0` IP address dynamically at boot and injects it as the advertising address:

```nix
systemd.services.loki.after = [ "tailscaled.service" "network-online.target" ];
systemd.services.loki.wants = [ "tailscaled.service" "network-online.target" ];
systemd.services.loki.serviceConfig.ExecStart = lib.mkForce (
  "/bin/sh -c '"
  + "TAILSCALE_IP=\"\"; "
  + "while [ -z \"$TAILSCALE_IP\" ]; do "
  + "  TAILSCALE_IP=$(tailscale ip -4 | head -n1); "
  + "  if [ -z \"$TAILSCALE_IP\" ]; then sleep 1; fi; "
  + "done; "
  + "export LOKI_CLUSTER_IP=$TAILSCALE_IP; "
  + "JOIN_OBS1=$(tailscale ip -4 proxmox-observability-1 | head -n1); "
  + "export JOIN_OBSERVABILITY_1=\"\${JOIN_OBS1:-proxmox-observability-1}:7946\"; "
  + "JOIN_OBS2=$(tailscale ip -4 proxmox-observability-2 | head -n1); "
  + "export JOIN_OBSERVABILITY_2=\"\${JOIN_OBS2:-proxmox-observability-2}:7946\"; "
  + "JOIN_RPI=$(tailscale ip -4 rpi4 | head -n1); "
  + "export JOIN_RPI4=\"\${JOIN_RPI:-rpi4}:7946\"; "
  + "exec ${pkgs.loki}/bin/loki "
  + "-memberlist.advertise-addr=$TAILSCALE_IP "
  + "-memberlist.bind-port=7946 "
  + "-memberlist.join=$JOIN_OBSERVABILITY,$JOIN_RPI4"
  + "'"
);
```

## Key Configurations

- **Json Output**: Explicitly forces json logging logs format using flag `-log.format=json`.
- **Gossip Eviction Tuning**: Memberlist eviction parameters are tuned for fast node state recoveries:
    - `dead_node_reclaim_time`: `30s` (allows fast cleanup of terminated nodes).
    - `gossip_interval`: `2s`.
- **Replication**: Ingestion ring replication factor is set to `1` (relies on S3-level Garage replication factor of 2).
