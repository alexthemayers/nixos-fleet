# Coder Service Configuration

This document describes the deployment and configuration details of the **Coder** service in the `nixos-fleet`
infrastructure.

## Overview

Coder is an enterprise-grade cloud development environment platform. It is deployed on the gaming and compilation host,
**`proxmox-gaming`**.

## Networking and Ports

- **Internal Port**: `7080` (TCP, HTTP)
- **Metrics Interface**: Listen on `0.0.0.0:2112` for Prometheus scraping.
- **Public Domain**: `https://coder.alexmayers.co.za` (reverse proxied by Caddy).

## Secrets Management

- **`postgres/coder_password`**: Password used to build the connection string for database access.
- **`coder/client_secret`**: OIDC client secret for Keycloak authentication.

Secrets are rendered into `/run/secrets/coder-env` using `sops.templates` and loaded via systemd's `EnvironmentFile` to
prevent exposing secrets in the Nix store.

## Database Integration

Coder connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `coder`
- **Port**: `5432` (PgBouncer)
- **Pool Mode**: Connection is forced to **session** pooling mode in PgBouncer configs since Coder workspace
  provisioning scripts require session-specific features.

## Configurations

- **Custom Nix Derivation**: Because NixOS does not package the desired version of Coder, the module compiles Coder
  `2.33.8` directly from GitHub using a custom derivation (`pkgs.stdenvNoCC.mkDerivation`), wrapping it to make sure
  `terraform` is available in its execution `PATH`.
- **SSO Authentication**: Login via standard username/password is disabled. Users must authenticate through Keycloak (
  `CODER_DISABLE_PASSWORD_AUTH=true`):
    - **OIDC Issuer**: `https://identity.alexmayers.co.za/realms/master`
    - **Scopes**: `openid,profile,email,offline_access`
- **Workspace Integration**: Coder runs as a system user `coder` and is added to the `docker` and `podman` system
  groups, allowing Coder workspaces to spawn rootless containers on the host system.
