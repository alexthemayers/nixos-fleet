# How-To: Configure the Caddy Reverse Proxy

Public HTTPS terminates on `xcloud-caddy` (`services/caddy.nix`). Almost every
vhost then forwards to `proxmox-lb:80`. The internal Caddy
(`services/caddy-internal.nix`) owns backends, health checks, and cookie or
`first` policies. Edge Caddy does not list `rpi4`. Four hubs stay SPOFs
([adr/2026-08-29-four-hubs.md](adr/2026-08-29-four-hubs.md),
[adr/2026-09-06-vaultwarden-no-edge-failover.md](adr/2026-09-06-vaultwarden-no-edge-failover.md)).

## 1. Two-tier routing

Add the public vhost on the edge. Keep the Host header and send traffic to the
internal load balancer. Put the real upstreams in `caddy-internal.nix`.

```nix
"https://myservice.alexmayers.co.za" = {
  extraConfig = ''
    ''${rateLimitStandard "myservice"}
    ''${wafDetectionMode}
    reverse_proxy proxmox-lb:80
  '';
};
```

Internal Grafana is cookie-balanced across the two observability VMs. The Pi
is not an upstream.

```caddy
reverse_proxy proxmox-observability-1:3000 proxmox-observability-2:3000 {
  lb_policy cookie grafana_lb
  health_uri /api/health
  health_interval 5s
  health_timeout 2s
  health_status 200
  flush_interval -1
}
```

## 2. Web Application Firewall (WAF)

Coraza + OWASP CRS runs in **DetectionOnly**. Matches are logged; they do not
block. See [adr/2026-08-29-waf-detection-only.md](adr/2026-08-29-waf-detection-only.md).
`${wafDetectionModeWith ''...''}` disables specific rules on paths that would
otherwise spam logs (Grafana).

```nix
"https://myservice.alexmayers.co.za" = {
  extraConfig = ''
    ''${wafDetectionMode}
    reverse_proxy proxmox-lb:80
  '';
};
```

## 3. Tier-based rate limiting

Zones are per `{remote_host}` over a 1 minute window. Tailscale
(`100.64.0.0/10`) and loopback are exempt where the zone has a `match`.

- `${rateLimitStandard "appname"}`: 500 events/min
- `${rateLimitHeavy "appname"}`: 1000 events/min
- `${rateLimitUltraHeavy "appname"}`: 2000 events/min
- Vaultwarden has its own pair (100/min on `/identity/connect/token`, 1000/min
  otherwise)

## 4. Forward auth (per vhost)

oauth2-proxy is **not** fleet-wide
([adr/2026-08-29-oauth2-proxy-coverage.md](adr/2026-08-29-oauth2-proxy-coverage.md)).
Use `${forwardAuth}` or `${hybridForwardAuth}` only on the vhosts that need it
(Grafana hybrid; budget, paperless, proxmox, truenas). Keycloak has none; it is
the IdP.

```nix
"https://budget.alexmayers.co.za" = {
  extraConfig = ''
    ''${forwardAuth}
    reverse_proxy proxmox-lb:80
  '';
};
```

`${hybridForwardAuth}` leaves Bearer API traffic alone and still redirects the
browser UI.

## 5. Keycloak `/admin` (Tailscale source IP)

`https://identity.alexmayers.co.za/admin*` is `abort`ed unless Caddy's
`remote_ip` is in `100.64.0.0/10`. There is no oauth2-proxy on identity.

A workstation with Tailscale up still uses the **WAN** source IP when DNS
points at `xcloud-caddy`'s public address. Pin `identity.alexmayers.co.za` to
xcloud-caddy's tailnet IPv4 (`/etc/hosts` or Tailscale split DNS), SOCKS
through a fleet node (`ssh -D 1080 root@proxmox-applications-1`), or browse
from a fleet node. `dig` ignores `/etc/hosts`. Login is Keycloak `admin` (sops
bootstrap secret). Full steps:
[services/keycloak.md](services/keycloak.md#accessing-the-admin-console).
