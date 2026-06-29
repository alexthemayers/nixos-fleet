# Mimir Metrics Aggregation Service Configuration

This document describes the deployment and configuration details of the **Grafana Mimir** service in the `nixos-fleet`
infrastructure.

## Overview

Grafana Mimir provides long-term storage for Prometheus metrics. In this fleet, it is deployed in a clustered
configuration across the observability node, **`proxmox-observability`**, and the backup node, **`rpi4`**.

## Networking and Ports

Mimir exposes the following ports, allowed strictly on the Tailscale firewall:

- **`9009`**: HTTP port (scraped by Grafana).
- **`9096`**: gRPC interface.
- **`7947`**: Memberlist gossip port (TCP/UDP, used for cluster communication and ring state synchronization).

## Secrets Management

- **`mimir/s3_access_key`** & **`mimir/s3_secret_key`**: S3 API keys used to authenticate metrics block writes on
  Garage.

Secrets are rendered into `mimir.env` and loaded as systemd service environment variables.

## Storage and Compactor

- **Storage Backend**: Metric block files (TSDB format) are stored in the replicated Garage S3 storage cluster bucket
  named `mimir` on `proxmox-db:3902`.
- **Local Directory**: Temporary TSDB files and cache blocks are stored at `/var/lib/mimir/tsdb`.

## Clustering and Gossip Resolution

Mimir runs as a cluster using memberlist gossip. To prevent hardcoding IPs, a systemd launcher override retrieves the
local `tailscale0` IP address dynamically at boot and injects it as the advertising address for the memberlist,
ingester, store-gateway, compactor, distributor, and querier components:

```nix
systemd.services.mimir.serviceConfig.ExecStart = lib.mkForce (
  "/bin/sh -c '"
  + "TAILSCALE_IP=$(ip -4 addr show dev tailscale0 | awk \"/inet / {print \\$2}\" | cut -d/ -f1); "
  + "exec ${pkgs.mimir}/bin/mimir "
  + "-memberlist.advertise-addr=$TAILSCALE_IP "
  + "-memberlist.advertise-port=7947 "
  + "-memberlist.bind-port=7947 "
  + "-memberlist.join=proxmox-observability:7947,rpi4:7947 "
  + "-ingester.ring.instance-addr=$TAILSCALE_IP "
  + "-store-gateway.sharding-ring.instance-addr=$TAILSCALE_IP "
  + "-compactor.ring.instance-addr=$TAILSCALE_IP "
  + "-distributor.ring.instance-addr=$TAILSCALE_IP "
  + "-querier.ring.instance-addr=$TAILSCALE_IP"
  + "'"
);
```

## Key Configurations

- **Single Binary Deploy**: Configured with `target = "all"` to run all Mimir services inside a single process,
  simplifying operations on the Raspberry Pi.
- **Limits**: Multitenancy is disabled (`multitenancy_enabled = false`). Ingestion rate limit is disabled (
  `ingestion_rate = 0`) to prevent packet drops during heavy metrics bursts.
- **Ring Eviction Tuning**: Gossip eviction parameters are tuned for fast node state recoveries:
    - `dead_node_reclaim_time`: `30s` (allows fast cleanup of terminated nodes).
    - `gossip_interval`: `2s`.
- **Replication**: Ingestion ring replication factor is set to `1` (relies on S3-level Garage replication factor of 2).
