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
- **Session Store**: Session states are offloaded to Redis at `redis://xcloud-postgres:6379` to support stateless proxy
  reboots. The Redis instance runs on `xcloud-postgres`, not alongside oauth2-proxy on `xcloud-caddy`, so the session
  store is reached over the tailnet and is password-authenticated:

  ```nix
  # on xcloud-postgres (services/redis.nix)
  services.redis.servers.oauth2-proxy = {
    enable = true;
    port = 6379;
    requirePassFile = config.sops.secrets."redis/oauth2_proxy_password".path;
    settings."protected-mode" = "yes";
  };
  ```

  The password reaches oauth2-proxy through `OAUTH2_PROXY_REDIS_PASSWORD` in a sops template, never on the command line
  or in the Nix store.
- **OIDC Provider**: Integrated with Keycloak realm master using client ID `oauth2-proxy`:
    - **Issuer URL**: `https://identity.alexmayers.co.za/realms/master`
    - **Challenge**: S256 PKCE enabled.
    - **Domains**: Allowed email domain set to `*` (filtered at the application level like Grafana).
- **Log Formatting**: Overrides request, authorization, and standard logs to write structured JSON:
  ```nix
  standard-logging-format = ''{"timestamp":"{{.Timestamp}}","file":"{{.File}}","msg":"{{.Message}}"}'';
  ```
