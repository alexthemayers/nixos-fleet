---
status: accepted
date: 2026-11-05
---

# Grafana Bearer `/api/*` skips per-vhost forward-auth

## Context and Problem Statement

Grafana is the only public vhost on `edge.auth = "hybrid"`. Hybrid still
sends every `/api/*` request through oauth2-proxy and only suppresses the
redirect, so a Grafana service-account Bearer token never reaches Grafana.
Public MCP clients need that token path without opening the browser UI.

## Decision Drivers

* MCP and other headless clients authenticate with a Grafana service-account
  token, not an oauth2-proxy cookie.
* The browser UI must stay on oauth2-proxy then Grafana Keycloak login.
* Opening all of `/api/*` would publish `/api/login` and Basic auth past the
  edge.
* The next hybrid vhost must not inherit an open API by default.

## Considered Options

* Skip oauth2-proxy for `Authorization: Bearer` on `/api/*` only, opt-in
  via `edge.apiBearerBypass` on the Grafana vhost
* Open all of `/api/*` (no Bearer matcher)
* Change the shared `hybridForwardAuth` snippet for every hybrid vhost
* Leave the edge gate closed and tunnel MCP over Tailscale only

## Decision Outcome

Chosen option: "Skip oauth2-proxy for `Authorization: Bearer` on `/api/*`
only, opt-in via `edge.apiBearerBypass` on the Grafana vhost", because that
is the credential MCP sends, keeps the UI on the double gate, and leaves
the shared hybrid snippet unchanged when the flag is off.

### Consequences

* Good, because a Viewer service-account token works from the public
  internet for Grafana API and datasource queries.
* Good, because `/api/login`, Basic auth, cookie-only API calls, `/apis/*`,
  and the UI still hit oauth2-proxy.
* Bad, because whoever holds the token can do what that Grafana role can
  do, including queries into Mimir, Loki, and Alertmanager, with no second
  factor at the edge.
* Bad, because a leaked Viewer token is a public credential until revoked
  in Grafana.

## Validation

`edge.apiBearerBypass` eval-fails unless `edge.auth = "hybrid"`. After
`xcloud-caddy` switch, a Bearer call to `/api/health` or `/api/user`
reaches Grafana; a cookieless `/login` still redirects to Keycloak.

## More Information

* [grafana.md](../services/grafana.md)
* [caddy.md](../services/caddy.md)
* [how-to-reverse-proxy.md](../how-to-reverse-proxy.md)
* [2026-08-29-oauth2-proxy-coverage.md](2026-08-29-oauth2-proxy-coverage.md)
