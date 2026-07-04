# OAuth2 Proxy Service Configuration

This document describes the deployment and configuration details of the **OAuth2 Proxy** service in the `nixos-fleet`
infrastructure.

## Overview

OAuth2 Proxy secures internal web interfaces (Grafana, Prometheus, Alertmanager, Proxmox, TrueNAS, actualbudget,
paperless) by integrating them with Keycloak OIDC authentication. It is deployed on the cloud gateway node, *
*`xcloud-caddy`**.

## Networking and Ports

- **Internal Port**: `4180` (TCP, HTTP), bound to localhost for Caddy's `forward_auth` queries.
- **Metrics Interface**: Listens on `0.0.0.0:44180` for metrics scraping.
- **Public Callback**: Route callback traffic goes to `https://auth.alexmayers.co.za/oauth2/callback`.

## Secrets Management

- **`oauth2-proxy/client_secret`**: Client secret used to authorize requests against the Keycloak OIDC issuer.
- **`oauth2-proxy/cookie_secret`**: Secret key used to encrypt cookie states.

Secrets are decrypted using SOPS and mapped to owner `oauth2-proxy:oauth2-proxy`.

## Key Configurations

- **SSO Scoping**: The cookie domain is set to `.alexmayers.co.za` to allow single sign-on (SSO) across all subdomains.
  Cookies are marked as secure.
- **Session Store**: Session states are offloaded to Redis (`redis://127.0.0.1:6379`) to support stateless proxy
  reboots:
  ```nix
  services.redis.servers.oauth2-proxy = {
    enable = true;
    port = 6379;
  };
  ```
- **OIDC Provider**: Integrated with Keycloak realm master using client ID `oauth2-proxy`:
    - **Issuer URL**: `https://identity.alexmayers.co.za/realms/master`
    - **Challenge**: S256 PKCE enabled.
    - **Domains**: Allowed email domain set to `*` (filtered at the application level like Grafana).
- **Log Formatting**: Overrides request, authorization, and standard logs to write structured JSON:
  ```nix
  standard-logging-format = ''{"timestamp":"{{.Timestamp}}","file":"{{.File}}","msg":"{{.Message}}"}'';
  ```
