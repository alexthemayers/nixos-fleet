# Keycloak Identity Provider Service Configuration

This document describes the deployment and configuration details of the **Keycloak** service in the `nixos-fleet`
infrastructure.

## Overview

Keycloak handles identity management and OIDC single sign-on (SSO) authentication across all services in the fleet. It
is deployed on the primary application node, **`proxmox-gitlab`**, with a failover instance deployed on **`rpi4`**.

## Networking and Ports

- **Internal Port**: `7777` (TCP)
- **Public Domain**: `https://identity.alexmayers.co.za` (reverse proxied via Caddy).
- **Failover / Clustering**: Caddy balances requests using `lb_policy first` and `fail_duration 10s` to redirect
  authentication flows to the Pi if the primary Proxmox host is down.

## Secrets Management

- **`postgres/keycloak_password`**: Password to authenticate connection requests to the PostgreSQL database.

## Database Integration

Keycloak connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `keycloak`
- **Port**: `5432` (PgBouncer)
- **SSL**: Disabled locally (`useSSL = false`).

## Key Configurations

- **SSO Reverse Proxy Mapping**: Configured with `proxy-headers = "xforwarded"` to parse reverse proxy headers
  correctly.
- **Log Format**: Forwards standard outputs as JSON (`log-console-output = "json"`).
- **Cluster Gossip configuration**: To replicate active sessions between the `proxmox-gitlab` and `rpi4` hosts, the
  systemd unit configures JGroups clustering binding arguments targeting the Tailscale network interface:
  ```nix
  JAVA_OPTS_APPEND = "-Djgroups.bind.address=match-interface:tailscale0 -Djgroups.bind_addr=match-interface:tailscale0 -Djava.net.preferIPv4Stack=true";
  ```
- **Endpoints**: Exposes `/health` (on port `9000`) and prometheus `/metrics` natively.
- **Admin**: Sets up a default seed user `admin`.
