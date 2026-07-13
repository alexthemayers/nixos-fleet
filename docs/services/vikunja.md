# Vikunja Tasks Service Configuration

This document describes the deployment and configuration details of the **Vikunja** task manager service in the
`nixos-fleet` infrastructure.

## Overview

Vikunja is an open-source task management platform. It is deployed in a stateless clustered architecture across *
*`proxmox-applications-1`** and **`proxmox-applications-2`**.

## Networking and Ports

- **Internal Port**: `3456` (TCP, HTTP)
- **Public Domain**: `https://tasks.alexmayers.co.za` (reverse proxied via Caddy).

## Secrets Management

- **`postgres/vikunja_password`**: Password to connect to PostgreSQL database on xcloud-postgres.
- **`vikunja/client_secret`**: OIDC client secret for Keycloak SSO integration.

Secrets are rendered into `vikunja-sso.env` using `sops.templates` and loaded as service environments.

## Database Integration

Vikunja connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `vikunja`
- **Port**: `5432` (PgBouncer)

## Key Configurations

- **Keycloak SSO Integration**: Authentication uses Keycloak OIDC:
    - **Auth Endpoint**: `https://identity.alexmayers.co.za/realms/master`
    - **Logout Endpoint**: `https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/logout`
    - **Client ID**: `vikunja`
- **Registration**: User registration is disabled (`enableregistration = false`).
- **Structured Logging**: Outputs logs in JSON (`format = "structured"`) for Loki.
- **Metrics**: Native prometheus metrics endpoint is enabled (`metrics.enabled = true`).
