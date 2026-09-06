---
status: accepted
date: 2026-08-29
---

# Keycloak master realm and admin via tailnet CIDR

## Context and Problem Statement

The public identity vhost is the IdP. oauth2-proxy cannot sit in front of it.
`realms/master` is the operational realm (not a disposable bootstrap).

## Decision Outcome

- Keep `realms/master` as the live realm; do not treat a freeze as a coding
  bug.
- Edge Caddy `abort`s `/admin*` unless `remote_ip` is in `100.64.0.0/10`.
- Login is Keycloak user `admin` (sops bootstrap secret). Changing sops does
  not rotate an existing DB user.

### Consequences

A laptop with Tailscale *up* still hits the WAN IP of `xcloud-caddy` unless
split DNS / MagicDNS sends `identity.alexmayers.co.za` to the tailnet address.
See [keycloak.md](../services/keycloak.md).

Public blackbox (obs-1 via WAN DNS) cannot probe `/admin*`. It probes OIDC
discovery instead (`services/prometheus.nix`).
