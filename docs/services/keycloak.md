# Keycloak Identity Provider Service Configuration

This document describes the deployment and configuration details of the **Keycloak** service in the `nixos-fleet`
infrastructure.

## Overview

Keycloak handles identity management and OIDC single sign-on (SSO) authentication across all services in the fleet. It
runs on **`proxmox-applications-1`** only (`cache=local`, no JGroups)
([no internal LB](../adr/2026-09-07-no-internal-lb.md)).
There is no `rpi4` instance; the Pi's replica was never routable and has been removed.

## Networking and Ports

- **Internal Port**: `7777` (TCP)
- **Public Domain**: `https://identity.alexmayers.co.za` (reverse proxied via Caddy).
- **Failover / Clustering**: none. Edge Caddy proxies `proxmox-applications-1:7777`
  with a health check on `/health/ready` (management port `9000`).
- **Admin console**: see [Accessing the admin console](#accessing-the-admin-console).
  `/admin*` is CIDR-gated to `100.64.0.0/10` on the edge Caddy. The public
  login (`https://identity.alexmayers.co.za`) stays reachable. Blackbox on
  obs-1 probes OIDC discovery, not `/admin*` ([prometheus.md](prometheus.md)).

## Accessing the admin console

URL: **`https://identity.alexmayers.co.za/admin`**

Edge Caddy (`services/caddy.nix`) `abort`s any request whose path is `/admin*` unless `remote_ip` is in
`100.64.0.0/10` (Tailscale CGNAT). There is **no** oauth2-proxy on this vhost: Keycloak *is* the IdP, so
forward-auth cannot sit in front of it. The gate is source IP only.

```
laptop  --public DNS-->  xcloud-caddy WAN   -->  abort (not 100.64/10)
laptop  --tailnet IP-->  xcloud-caddy :443  -->  Keycloak :7777
```

**Tailscale being connected is not enough.** Public DNS for `identity.alexmayers.co.za` points at
`xcloud-caddy`'s WAN address. The TCP session then originates from your ISP address, Caddy sees a public
`remote_ip`, and the connection is reset. The laptop's tailnet IP is unused unless the name resolves to
the tailnet.

Ways that work:

1. **Pin the name to `xcloud-caddy`'s tailnet IPv4 on the laptop** so the browser
   session originates in `100.64.0.0/10` while Tailscale is up. Do not point the
   name at apps-1/apps-2: TLS and the CIDR check both terminate on
   `xcloud-caddy`. Look the address up; do not copy a stale CGNAT IP from an
   old note:

   ```bash
   tailscale ip -4 xcloud-caddy
   ```

   Then either:

   - **`/etc/hosts`** (local, no Tailscale admin change). Append
     `<that-ipv4> identity.alexmayers.co.za`. Keep Tailscale connected and open
     the URL. `dig` queries public DNS and **ignores** `/etc/hosts`; a WAN A
     record from `dig +short` does not mean the pin failed. Confirm the OS
     resolver instead (`ping identity.alexmayers.co.za` or, on macOS,
     `dscacheutil -q host -a name identity.alexmayers.co.za`). Chrome "Use
     secure DNS" and Firefox DNS over HTTPS also bypass `/etc/hosts`; turn
     those off for this profile or use Safari. Remove the hosts line to return
     to public DNS.
   - **Split DNS** (Tailscale admin console, not this repo): the same A record,
     fleet-wide, so every node with Tailscale up sources from `100.64.0.0/10`.

2. **SOCKS through a fleet node**:
   ```bash
   ssh -D 1080 root@proxmox-applications-1
   ```
   Point the browser at `socks5://127.0.0.1:1080` (or `socks5h` so DNS also goes through the proxy) and
   open the URL. The edge then sees the node's `100.64.0.0/10` address.
3. **Browse on a fleet node** that already has a desktop/browser on the tailnet (`gaming`, a Coder
   workspace, etc.).

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
- **Jellyfin roles**: `jellyfin:read` is a child of
  `default-roles-master`, so every realm user has library access.
  Group `jellyfin admin` maps to `jellyfin:admin` for the dashboard. The
  `jellyfin` client emits those client roles on the OIDC `roles` claim.
  See [jellyfin.md](jellyfin.md) and
  [adr/2026-09-04-jellyfin-sso-groups.md](../adr/2026-09-04-jellyfin-sso-groups.md).
- **Grafana roles**: same pattern. `grafana:read` is a child of
  `default-roles-master` (`Viewer`). Group `grafana admin` maps to
  `grafana:admin` (`GrafanaAdmin`). The `grafana` client emits those
  client roles on the OIDC `roles` claim. See [grafana.md](grafana.md)
  and
  [adr/2026-09-07-grafana-sso-groups.md](../adr/2026-09-07-grafana-sso-groups.md).

## Alerting

Rules live in the `keycloak` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix).
Dashboard: Keycloak Quarkus. JVM heap is unbounded; see
[memory.md](../memory.md).

| Alert | Catches |
|---|---|
| `KeycloakServerErrorRate` | `outcome="SERVER_ERROR"` above 5% |
