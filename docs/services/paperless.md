# Paperless-ngx Service Configuration

This document describes the deployment and configuration details of the **Paperless-ngx** document management service in the `nixos-fleet` infrastructure.

## Overview
Paperless-ngx archives, indexes, and performs OCR on scanned documents. It is deployed on the primary application node, **`proxmox-gitlab`**.

## Networking and Ports
- **Internal Port**: `28981` (TCP)
- **Public Domain**: `https://paperless.alexmayers.co.za` (reverse proxied via Caddy).

## Secrets Management
- **`postgres/paperless_password`**: Password to connect to PostgreSQL database on xcloud-postgres.
- **`paperless/admin_password`**: Password for the seed admin account.
- **`paperless/client_secret`**: OIDC client secret for Keycloak SSO integration.

Secrets are rendered into `paperless.env` using `sops.templates` and loaded as service environments.

## Database Integration
Paperless connects to the central PostgreSQL database instance:
- **Host**: `xcloud-postgres`
- **Database/User**: `paperless`
- **Port**: `5432` (PgBouncer)

## Storage and NFS Mounts
Paperless stores files directly on the NAS:
- **NFS Share**: `truenas-scale:/mnt/ssd/paperless` is mounted to `/mnt/nfs/paperless` (and configured as paperless `dataDir`).
- **Wait Service**: Mount depends on `wait-for-host-paperless.service` to prevent boot blocks if NAS connection is slow.
- **Directory Initialization**: A custom helper service `paperless-create-dirs` runs before the main paperless services start (consumer, scheduler, task-queue, web-server) to initialize subdirectories:
  - `/mnt/nfs/paperless/consume` (document drop/import directory)
  - `/mnt/nfs/paperless/media` (document storage directory)
- **Sandboxing**: Each paperless systemd service contains a `RequiresMountsFor = [ "/mnt/nfs/paperless" ]` block.

## Key Configurations
- **Keycloak SSO Integration**: Authentication uses Django `allauth` generic OpenID Connect providers:
  - **Issuer**: `https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration`
  - **Client ID**: `paperless`
  - **Provider Settings**: Auto-signup is enabled (`PAPERLESS_SOCIALACCOUNT_AUTO_SIGNUP = "true"`), and email verification is bypassed.
- **Trusted Proxies**: Configured to trust Caddy headers from the Tailscale subnet (`PAPERLESS_TRUSTED_PROXIES = "100.64.0.0/10"`).
