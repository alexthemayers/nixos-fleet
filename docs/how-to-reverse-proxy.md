# How-To: Configure the Caddy Reverse Proxy

Public HTTPS terminates on `xcloud-caddy` (`services/caddy.nix`). Every
public vhost and UDP game port is generated from
[`fleet/apps/`](../fleet/apps/). There is no internal load balancer
([adr/2026-09-07-no-internal-lb.md](adr/2026-09-07-no-internal-lb.md)).
Three hubs stay SPOFs (`xcloud-caddy`, `xcloud-postgres`,
`truenas-scale`). Vaultwarden has no Pi failover
([adr/2026-09-06-vaultwarden-no-edge-failover.md](adr/2026-09-06-vaultwarden-no-edge-failover.md)).

## 1. One-tier routing

Add `fleet/apps/<name>.nix` with `host`, `port`, `module`, and `edge` (see
[custom-options.md](custom-options.md#app-registry-fleetapps)). Caddy
generates the vhost. flake.nix imports `module` on that `host`. Keep health
checks on any upstream that can listen while broken (Keycloak
`/health/ready` on `:9000`, not `/token`).

Example registry entry:

```nix
{
  host = "proxmox-applications-debian";
  port = 1234;
  docs = "docs/services/myservice.md";
  module = "services/myservice.nix";
  edge = {
    domain = "myservice.alexmayers.co.za";
    healthUri = "/health";
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "200";
  };
  probe.public = true;
}
```

Grafana is a single backend on `proxmox-observability`
(`fleet/apps/grafana.nix`). The Pi is not an upstream.

## 2. Web Application Firewall (WAF)

Coraza + OWASP CRS runs in **DetectionOnly**. Matches are logged; they do not
block. See [adr/2026-08-29-waf-detection-only.md](adr/2026-08-29-waf-detection-only.md).
Eval fails if a Coraza vhost is missing `DetectionOnly` or sets
`SecRuleEngine On`. Set `edge.wafExtraDirectives` to disable specific rules
on paths that would otherwise spam logs (Grafana, GitLab). `edge.waf = false`
skips Coraza (budget, paperless, Proxmox, TrueNAS).

## 3. Tier-based rate limiting

Zones are per `{remote_host}` over a 1 minute window. Tailscale
(`100.64.0.0/10`) and loopback are exempt. Set `edge.rateLimit` to
`standard` (500/min), `heavy` (1000/min), `ultraHeavy` (2000/min), or
`vaultwarden` (100/min on `/identity/connect/token`, 1000/min otherwise).
`edge.rateLimitZone` keeps the Caddy zone name when it differs from the
registry attr (`budget`, `identity`, `tasks`, `auth`, `registry`).

## 4. Forward auth (per vhost)

oauth2-proxy is **not** fleet-wide
([adr/2026-08-29-oauth2-proxy-coverage.md](adr/2026-08-29-oauth2-proxy-coverage.md)).
Set `edge.auth = "forward"` or `"hybrid"` only on the vhosts that need it
(Grafana hybrid; budget, paperless, proxmox, truenas). Keycloak has none;
it is the IdP. `edge.adminCidrPath = "/admin*"` aborts unless the client
is in `100.64.0.0/10`.

Grafana uses hybrid auth with `edge.apiBearerBypass`:
`Authorization: Bearer` on `/api/*` skips oauth2-proxy so Grafana can
authenticate a service-account token; other `/api/*` calls still hit
oauth2-proxy without a redirect; the browser UI still goes to Keycloak
([adr/2026-11-05-grafana-api-bearer-bypass.md](adr/2026-11-05-grafana-api-bearer-bypass.md)).

## 5. Keycloak `/admin` (Tailscale source IP)

`https://identity.alexmayers.co.za/admin*` is `abort`ed unless Caddy's
`remote_ip` is in `100.64.0.0/10`. There is no oauth2-proxy on identity.

A workstation with Tailscale up still uses the **WAN** source IP when DNS
points at `xcloud-caddy`'s public address. Pin `identity.alexmayers.co.za` to
xcloud-caddy's tailnet IPv4 (`/etc/hosts` or Tailscale split DNS), SOCKS
through a fleet node (`ssh -D 1080 root@proxmox-applications-debian`), or browse
from a fleet node. `dig` ignores `/etc/hosts`. Login is Keycloak `admin` (sops
bootstrap secret). Full steps:
[services/keycloak.md](services/keycloak.md#accessing-the-admin-console).
