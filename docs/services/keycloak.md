# Keycloak Identity Provider Service Configuration

This document describes the deployment and configuration details of the **Keycloak** service in the `nixos-fleet`
infrastructure.

## Overview

Keycloak handles identity management and OIDC single sign-on (SSO) authentication across all services in the fleet. It
is deployed in a stateless clustered architecture across **`proxmox-applications-1`** and **`proxmox-applications-2`**.
There is no `rpi4` instance; the Pi's replica was never routable and has been removed.

## Networking and Ports

- **Internal Port**: `7777` (TCP)
- **Public Domain**: `https://identity.alexmayers.co.za` (reverse proxied via Caddy).
- **Failover / Clustering**: the internal Caddy on `proxmox-lb` balances the two instances with `lb_policy round_robin`
  and active health checks; JGroups session replication means either instance can serve any authentication flow.
- **Admin console**: see [Accessing the admin console](#accessing-the-admin-console). `/admin*` is CIDR-gated
  to `100.64.0.0/10` on the edge Caddy. The public login (`https://identity.alexmayers.co.za`) stays reachable.

## Accessing the admin console

URL: **`https://identity.alexmayers.co.za/admin`**

Edge Caddy (`services/caddy.nix`) `abort`s any request whose path is `/admin*` unless `remote_ip` is in
`100.64.0.0/10` (Tailscale CGNAT). There is **no** oauth2-proxy on this vhost: Keycloak *is* the IdP, so
forward-auth cannot sit in front of it. The gate is source IP only.

```
laptop  --public DNS-->  xcloud-caddy WAN   -->  abort (not 100.64/10)
laptop  --tailnet IP-->  xcloud-caddy :443  -->  proxmox-lb:80  -->  Keycloak :7777
```

**Tailscale being connected is not enough.** Public DNS for `identity.alexmayers.co.za` points at
`xcloud-caddy`'s WAN address. The TCP session then originates from your ISP address, Caddy sees a public
`remote_ip`, and the connection is reset. The laptop's tailnet IP is unused unless the name resolves to
the tailnet.

Ways that work:

1. **SOCKS through a fleet node** (usual operator path from a laptop):
   ```bash
   ssh -D 1080 root@proxmox-applications-1
   ```
   Point the browser at `socks5://127.0.0.1:1080` (or `socks5h` so DNS also goes through the proxy) and
   open the URL. The edge then sees the node's `100.64.0.0/10` address.
2. **Browse on a fleet node** that already has a desktop/browser on the tailnet (`gaming`, a Coder
   workspace, etc.).
3. **Split DNS** (Tailscale admin console, not this repo): make `identity.alexmayers.co.za` resolve to
   **xcloud-caddy's tailnet IPv4**. Then a laptop with Tailscale up sources from `100.64.0.0/10` and
   `/admin` is allowed. Do not point the name at apps-1/apps-2: TLS and the CIDR check both terminate
   on `xcloud-caddy`.

Login is Keycloak user **`admin`**. The password is `keycloak/bootstrap_admin_password` in
`secrets/proxmox-applications-1/secrets.yaml` (same value on apps-2). Edit with
`make edit-secrets HOST=proxmox-applications-1`. Changing that sops key does **not** rotate an
existing database user; it only affects bootstrap of a new realm.

The operational realm is `realms/master`
([adr/2026-08-29-keycloak-master.md](../adr/2026-08-29-keycloak-master.md)).

## Secrets Management

- **`postgres/keycloak_password`**: Password to authenticate connection requests to the PostgreSQL database.
- **`keycloak/bootstrap_admin_password`**: Password for the initial `admin` account. This is delivered through a sops
  template as `KC_BOOTSTRAP_ADMIN_PASSWORD` in an `EnvironmentFile`, **not** via `services.keycloak.initialAdminPassword`
  — that option writes the password into a world-readable file in the Nix store.

## Database Integration

Keycloak connects to the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `keycloak`
- **Port**: `5432` (PgBouncer)
- **SSL**: Disabled locally (`useSSL = false`).
- **Boot**: `fleet.waitForHost.keycloak-postgres` waits up to 600s for `xcloud-postgres:5432` before `keycloak.service`
  starts. If Keycloak then exits, systemd `Restart=always` (no start limit) crashloops it rather than leaving SSO down.

## Key Configurations

- **SSO Reverse Proxy Mapping**: Configured with `proxy-headers = "xforwarded"` to parse reverse proxy headers
  correctly.
- **Log Format**: Forwards standard outputs as JSON (`log-console-output = "json"`).
- **Cluster Gossip configuration**: To replicate active sessions between the `proxmox-applications-1` and
  `proxmox-applications-2` hosts, the
  systemd unit configures JGroups clustering binding arguments targeting the Tailscale network interface:
  ```nix
  JAVA_OPTS_APPEND = "-Djgroups.bind.address=match-interface:tailscale0 -Djgroups.bind_addr=match-interface:tailscale0 -Djava.net.preferIPv4Stack=true";
  ```
- **Endpoints**: Exposes `/health` (on port `9000`) and prometheus `/metrics` natively.
- **Admin**: Sets up a default seed user `admin`. The password is
  `keycloak/bootstrap_admin_password` in sops. Changing that secret does **not**
  rotate an existing database user; it only affects bootstrap. There is no
  oauth2-proxy on this vhost (Keycloak is the IdP). See
  [adr/2026-08-29-keycloak-master.md](../adr/2026-08-29-keycloak-master.md).
