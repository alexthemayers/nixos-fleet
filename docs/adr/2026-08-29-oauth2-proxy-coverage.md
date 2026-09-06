---
status: accepted
date: 2026-08-29
---

# oauth2-proxy is not fleet-wide forward-auth

## Context and Problem Statement

[docs/standards.md](../standards.md) previously described unified
`forward_auth` to oauth2-proxy + Keycloak. Several public vhosts do not use
that chain (Keycloak itself cannot, Vaultwarden, games, some APIs).

## Decision Outcome

oauth2-proxy is an optional Caddy snippet (`forwardAuth` /
`hybridForwardAuth`), applied per vhost. It is not a fleet-wide policy.

### Consequences

Identity (`identity.alexmayers.co.za`) has no oauth2-proxy; it *is* the IdP.
Admin for Keycloak is CIDR-gated instead
([2026-08-29-keycloak-master.md](2026-08-29-keycloak-master.md)).
