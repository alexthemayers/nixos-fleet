# Actual Budget Service Configuration

This document describes the deployment and configuration details of the **Actual Budget** service in the `nixos-fleet`
infrastructure.

## Overview

Actual Budget is a privacy-focused personal finance manager. In this fleet, it is deployed on the general application
node, **`proxmox-applications-debian`**.

## Networking and Ports

- **Internal Port**: `5006` (TCP). Pinned in `services/actualbudget.nix`; the
  nixpkgs module default is `3000`.
- **Public Domain**: `https://budget.alexmayers.co.za` (reverse proxied via
  Caddy on `xcloud-caddy`).
- **OAuth/SSO Bypass**: Traffic passing through Caddy is protected by Keycloak SSO forward authentication (
  `oauth2-proxy`).

## Secrets Management

The service requires client secrets for OIDC authentication:

- **`actualbudget/client_secret`**: OpenID Connect client secret for authenticating with Keycloak. Decrypted by SOPS
  with ownership set to the system user `actual`.

## Storage and Mounts

To protect transaction data, storage is mounted from the NAS:

- **NFS Share**: `truenas-scale:/mnt/ssd/actualbudget` is mounted to `/mnt/nfs/actualbudget`.
- **Systemd Dependency**: The mount waits via
  `fleet.waitForHost.actualbudget.host = "truenas-scale"` (unit
  `wait-for-host-actualbudget`) so boot does not race the NAS.
- **Service Sandboxing**: The service's systemd configuration uses `BindPaths` to securely map the NFS storage to the
  private directory `/var/lib/private/actual`.

## Key Configurations

- **SSO Integration**: Configured to use Keycloak for authentication (`authMethod = "openid"`) using discovery URL:
  `https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration`
- **Node**: The Debian unit runs Node 22.23.4 from `/opt/node-v22`.
  `@actual-app/sync-server` 26.11.0 requires Node `>=22.19.0`. Apt's Node 20
  segfaults during OpenID discovery, before the process listens.
  `/usr/bin/node` stays that apt package. `actual.service` puts
  `/opt/node-v22/bin` first on `PATH`.
- **OpenID stays configured**. A failed start does not rewrite
  `/etc/actual/config.json` to password login. The unit uses
  `Restart=on-failure` and `RestartSec=10`.
- **Service User**: Runs under a dedicated system user/group `actual`.
