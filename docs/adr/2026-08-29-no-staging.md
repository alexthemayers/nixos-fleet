# ADR: No staging; merge to main deploys

**Status:** accepted (2026-08-29)

## Context

There is no staging fleet. Partial deploys and co-routed package skew (Keycloak,
Grafana) are the risk.

## Decision

A merge to `main` is a production deploy (GitLab deploy jobs, after
verify-from-attic). `gaming` stays manual. There is no separate staging
environment to promote from.

## Consequences

Lint + inventory + exclusive realize are the gates. `flake.nix` `co-routed-peers`
check exists because apps-1/apps-2 and obs-1/obs-2 can otherwise drift.
Rollback is per-host generations ([rollback.md](../runbooks/rollback.md)).
