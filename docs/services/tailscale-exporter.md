# Tailscale Exporter Service Configuration

This document describes the deployment and configuration details of the **Tailscale Prometheus Exporter** service in the
`nixos-fleet` infrastructure.

## Overview

The Tailscale Exporter scrapes device connectivity status and network information from the Tailscale daemon and exposes
them to Prometheus. It is deployed on the observability node, **`proxmox-observability-1`**.

## Networking and Ports

- **Metrics Interface**: Exposes Tailscale node metrics.
- **Scraped by**: Prometheus on `proxmox-observability-1:9090`.

## Secrets Management

- **`tailscale/exporter_env`**: Contains the API access tokens or keys required to authorize client queries against the
  Tailscale network daemon. Decrypted by SOPS and passed to the exporter.

## Key Configurations

- **Service User**: Runs under the dedicated system user `tailscale-exporter`.
- **Environment**: Reads configuration variables (such as tailscale API endpoints and credential paths) from the
  sops-decrypted file.
