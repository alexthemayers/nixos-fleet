# How-To: Configure the Caddy Reverse Proxy

The `nixos-fleet` centralizes external access through a highly customized Caddy reverse proxy (`services/caddy.nix`).
Rather than defining basic `reverse_proxy` blocks, we apply a standardized architecture involving Web Application
Firewalls (WAF), tier-based Rate Limiting, Active-Passive Load Balancing, and Single Sign-On (SSO).

## 1. Active-Passive Load Balancing

To ensure High Availability, critical services are deployed on a primary Proxmox cluster, with a fallback instance
running on a Raspberry Pi.

**Implementation**:
Specify multiple upstreams and use a load-balancing policy with health checks. Without `health_uri`, Caddy will
keep sending traffic to a dead backend.

Internal Grafana is cookie-balanced across the two observability VMs. The Pi is not an upstream.

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

We utilize the Coraza WAF plugin with OWASP Core Rule Sets to inspect traffic for SQL injection, cross-site scripting (
XSS), and other vulnerabilities.

**Implementation**:
Apply the `${wafDetectionMode}` snippet to your virtual host.

```nix
"https://myservice.alexmayers.co.za" = {
  extraConfig = ''
    ''${wafDetectionMode}
    reverse_proxy mybackend:8080
  '';
};
```

**Tradeoffs**:
Sometimes the WAF would block legitimate application traffic (False Positives). The
fleet keeps Coraza in **DetectionOnly**; matches are logged, not blocked. See
[adr/2026-08-29-waf-detection-only.md](adr/2026-08-29-waf-detection-only.md).
`${wafDetectionModeWith ''...''}` still exists to disable specific rules on paths
that would otherwise spam logs (Grafana).

## 3. Tier-Based Rate Limiting

To prevent brute force attacks and denial-of-service, all endpoints must be protected by a rate limit tier defined at
the top of `caddy.nix`.

**Implementation**:
Inject the appropriate tier macro at the top of your `extraConfig`.

- `''${rateLimitStandard "appname"}`: 200 req/min. Good for standard web UIs.
- `''${rateLimitHeavy "appname"}`: 1000 req/min. Good for media servers (Jellyfin, Immich) or heavily dynamic apps.
- `''${rateLimitUltraHeavy "appname"}`: 2000 req/min. For high-throughput internal APIs (S3, Mimir, Registry).

```nix
"https://myservice.alexmayers.co.za" = {
  extraConfig = ''
    ''${rateLimitStandard "myservice"}
    reverse_proxy mybackend:8080
  '';
};
```

## 4. Single Sign-On (Forward Auth)

We enforce zero-trust network access on internal tools using Keycloak and OAuth2-Proxy. Caddy intercepts requests,
checks auth, and redirects to the Keycloak login screen if unauthenticated.

**Implementation**:
Inject the `''${forwardAuth}` macro.

```nix
"https://budget.alexmayers.co.za" = {
  extraConfig = ''
    ''${forwardAuth}
    reverse_proxy proxmox-applications-1:5006
  '';
};
```

**Tradeoffs**:
Forward Auth completely blocks API access unless the client handles the OAuth2 redirect flow. For services that require
mixed access (APIs utilizing Bearer tokens alongside a Web UI), utilize the `''${hybridForwardAuth}` macro or bypass
auth entirely and let the application handle it natively. oauth2-proxy is per-vhost, not fleet-wide
([adr/2026-08-29-oauth2-proxy-coverage.md](adr/2026-08-29-oauth2-proxy-coverage.md)).

## 5. Keycloak `/admin` (Tailscale source IP)

`https://identity.alexmayers.co.za/admin*` is `abort`ed unless Caddy's `remote_ip`
is in `100.64.0.0/10`. There is no oauth2-proxy on identity.

A workstation with Tailscale up still uses the **WAN** source IP when DNS points
at `xcloud-caddy`'s public address. Pin `identity.alexmayers.co.za` to
xcloud-caddy's tailnet IPv4 (`/etc/hosts` or Tailscale split DNS), SOCKS through
a fleet node (`ssh -D 1080 root@proxmox-applications-1`), or browse from a
fleet node. `dig` ignores `/etc/hosts`. Login is Keycloak `admin` (sops
bootstrap secret). Full steps:
[services/keycloak.md](services/keycloak.md#accessing-the-admin-console).
