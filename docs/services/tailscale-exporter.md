# Tailscale Exporter Service Configuration

This document describes the deployment and configuration details of the **Tailscale Prometheus Exporter** service in the
`nixos-fleet` infrastructure.

## Overview

The Tailscale Exporter scrapes device connectivity status and network information from the Tailscale daemon and exposes
them to Prometheus. It runs on **`proxmox-observability-debian`** (Podman unit
`tailscale-exporter.service`).

## Networking and Ports

- **Metrics**: `:9250` (`--listen-address=:9250`).
- **Scraped by**: Prometheus on `proxmox-observability-debian:9090`
  (`job_name = "tailscale exporter"`).

## Secrets Management

- **`tailscale/exporter_env`**: Contains the API access tokens or keys required to authorize client queries against the
  Tailscale network daemon. Decrypted by SOPS and passed to the exporter.

## Key Configurations

- **Service User**: Runs under the dedicated system user `tailscale-exporter`.
- **Environment**: Reads configuration variables (such as tailscale API endpoints and credential paths) from the
  sops-decrypted file.
