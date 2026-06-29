# Actual Budget Service Configuration

This document describes the deployment and configuration details of the **Actual Budget** service in the `nixos-fleet`
infrastructure.

## Overview

Actual Budget is a privacy-focused personal finance manager. In this fleet, it is deployed on the primary application
node, **`proxmox-gitlab`**.

## Networking and Ports

- **Internal Port**: `5006` (TCP)
- **Public Domain**: `https://budget.alexmayers.co.za` (reverse proxied via Caddy on `xcloud-caddy`).
- **OAuth/SSO Bypass**: Traffic passing through Caddy is protected by Keycloak SSO forward authentication (
  `oauth2-proxy`).

## Secrets Management

The service requires client secrets for OIDC authentication:

- **`actualbudget/client_secret`**: OpenID Connect client secret for authenticating with Keycloak. Decrypted by SOPS
  with ownership set to the system user `actual`.

## Storage and Mounts

To protect transaction data, storage is mounted from the NAS:

- **NFS Share**: `truenas-scale:/mnt/ssd/actualbudget` is mounted to `/mnt/nfs/actualbudget`.
- **Systemd Dependency**: Mount options include `x-systemd.requires=actual-wait-for-nas.service` to prevent boot
  failures if the NAS is unavailable at startup.
- **Service Sandboxing**: The service's systemd configuration uses `BindPaths` to securely map the NFS storage to the
  private directory `/var/lib/private/actual`.

## Key Configurations

- **SSO Integration**: Configured to use Keycloak for authentication (`authMethod = "openid"`) using discovery URL:
  `https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration`
- **Wait Service (`actual-wait-for-nas`)**: A oneshot helper service that pings `truenas-scale` up to 120 seconds on
  boot to resolve MagicDNS before permitting the NFS mount.
- **Service User**: Runs under a dedicated system user/group `actual`.
