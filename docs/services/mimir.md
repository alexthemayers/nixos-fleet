# Mimir Metrics Aggregation Service Configuration

This document describes the deployment and configuration details of the **Grafana Mimir** service in the `nixos-fleet`
infrastructure.

## Overview

Grafana Mimir provides long-term storage for Prometheus metrics. In this fleet, it is deployed in a clustered
configuration across the observability nodes, **`proxmox-observability-1`**, **`proxmox-observability-2`**, and the
backup node, **`rpi4`**.

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
systemd.services.mimir.after = [ "tailscaled.service" "network-online.target" ];
systemd.services.mimir.wants = [ "tailscaled.service" "network-online.target" ];
systemd.services.mimir.serviceConfig.ExecStart = lib.mkForce (
  "/bin/sh -c '"
  + "TAILSCALE_IP=\"\"; "
  + "while [ -z \"$TAILSCALE_IP\" ]; do "
  + "  TAILSCALE_IP=$(tailscale ip -4 | head -n1); "
  + "  if [ -z \"$TAILSCALE_IP\" ]; then sleep 1; fi; "
  + "done; "
  + "export MIMIR_CLUSTER_IP=$TAILSCALE_IP; "
  + "JOIN_OBS1=$(tailscale ip -4 proxmox-observability-1 | head -n1); "
  + "export JOIN_OBSERVABILITY_1=\"\${JOIN_OBS1:-proxmox-observability-1}:7947\"; "
  + "JOIN_OBS2=$(tailscale ip -4 proxmox-observability-2 | head -n1); "
  + "export JOIN_OBSERVABILITY_2=\"\${JOIN_OBS2:-proxmox-observability-2}:7947\"; "
  + "JOIN_RPI=$(tailscale ip -4 rpi4 | head -n1); "
  + "export JOIN_RPI4=\"\${JOIN_RPI:-rpi4}:7947\"; "
  + "exec ${pkgs.mimir}/bin/mimir "
  + "-memberlist.advertise-addr=$TAILSCALE_IP "
  + "-memberlist.advertise-port=7947 "
  + "-memberlist.bind-port=7947 "
  + "-memberlist.join=$JOIN_OBSERVABILITY,$JOIN_RPI4 "
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
