# How-To: Configure the Caddy Reverse Proxy

The `nixos-fleet` centralizes external access through a highly customized Caddy reverse proxy (`services/caddy.nix`).
Rather than defining basic `reverse_proxy` blocks, we apply a standardized architecture involving Web Application
Firewalls (WAF), tier-based Rate Limiting, Active-Passive Load Balancing, and Single Sign-On (SSO).

## 1. Active-Passive Load Balancing

To ensure High Availability, critical services are deployed on a primary Proxmox cluster, with a fallback instance
running on a Raspberry Pi.

**Implementation**:
Specify multiple upstreams and use `lb_policy first`. You *must* configure health checks, or Caddy will never failover.

```caddy
reverse_proxy proxmox-observability:3000 rpi4:3000 {
  lb_policy first
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
Sometimes the WAF blocks legitimate application traffic (False Positives). When this happens, utilize
`${wafDetectionModeWith ''...''}` to disable specific rules for specific paths. See the Grafana configuration in
`caddy.nix` for an example of removing `SecRule` IDs.

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
    reverse_proxy proxmox-budget:5006
  '';
};
```

**Tradeoffs**:
Forward Auth completely blocks API access unless the client handles the OAuth2 redirect flow. For services that require
mixed access (APIs utilizing Bearer tokens alongside a Web UI), utilize the `''${hybridForwardAuth}` macro or bypass
auth entirely and let the application handle it natively.
