# ADR: WAF stays DetectionOnly

**Status:** accepted (2026-08-29)

## Context

Coraza + OWASP CRS is loaded on the edge Caddy. `SecRuleEngine DetectionOnly`
means matches are logged and never blocked. Media paths (`/api/media/*`,
`/socket*`, WebSocket upgrades) omit the WAF snippet entirely.

## Decision

Keep DetectionOnly. Blocking mode is a product change with false-positive
cost (Grafana, GitLab, Immich) that this fleet has not taken.

## Consequences

Do not describe the edge as a blocking WAF. Rate limits and oauth2-proxy (where
actually wired) are the enforcement that exists. See
[caddy.md](../services/caddy.md).
