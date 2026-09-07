# Prometheus Blackbox Exporter Service Configuration

The Blackbox Exporter probes public HTTPS endpoints. It runs on
**`proxmox-observability`**.

## Networking and Ports

- **Internal Port**: `9115` (TCP), `tailscale0` only.
- **Probe scrapes**: Prometheus `blackbox_http` relabels every target to
  `proxmox-observability:9115/probe`.
- **Process scrape**: job `blackbox` hits the same host `:9115/metrics`.

## Secrets Management

- **`oauth2-proxy/blackbox_token`**: injected as `X-Blackbox-Token` so
  oauth2-proxy vhosts accept the probe. Same value as on `xcloud-caddy`.

## Probe module

`http_2xx`: GET over HTTP/1.1 and HTTP/2, any 2xx. Identity is OIDC
discovery, not `/admin*`
([adr/2026-08-29-keycloak-master.md](../adr/2026-08-29-keycloak-master.md)).

## Alerting

`EndpointDown` watches `probe_success`. `TargetDown` ignores
`job="blackbox_http"` so a dead prober is one scrape-down, not fifteen
fake site-downs
([adr/2026-09-06-blackbox-on-obs-1.md](../adr/2026-09-06-blackbox-on-obs-1.md)).
Dashboard: `fleet-blackbox`.

Module: [`services/blackbox-exporter.nix`](../../services/blackbox-exporter.nix).
