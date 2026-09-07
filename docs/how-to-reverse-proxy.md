# How-To: Configure the Caddy Reverse Proxy

Public HTTPS terminates on `xcloud-caddy` (`services/caddy.nix`). Each
vhost reverse-proxies the serving VM over the tailnet. There is no
internal load balancer
([adr/2026-09-07-no-internal-lb.md](adr/2026-09-07-no-internal-lb.md)).
Three hubs stay SPOFs (`xcloud-caddy`, `xcloud-postgres`,
`truenas-scale`). Vaultwarden has no Pi failover
([adr/2026-09-06-vaultwarden-no-edge-failover.md](adr/2026-09-06-vaultwarden-no-edge-failover.md)).

## 1. One-tier routing

Add the public vhost on the edge. Point `reverse_proxy` at the process
port on the backend host. Keep health checks on any upstream that can
listen while broken.

```nix
"https://myservice.alexmayers.co.za" = {
  extraConfig = ''
    ''${rateLimitStandard "myservice"}
    ''${wafDetectionMode}
    reverse_proxy proxmox-applications-1:1234 {
      health_uri /health
      health_interval 5s
      health_timeout 2s
      health_status 200
    }
  '';
};
```

Grafana is a single backend on `proxmox-observability`. The Pi is not an
upstream.

```caddy
reverse_proxy proxmox-observability:3000 {
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
    reverse_proxy proxmox-applications-1:1234
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
    reverse_proxy proxmox-applications-1:5006
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
