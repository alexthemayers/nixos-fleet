---
status: accepted
date: 2026-08-29
---

# No staging; merge to main deploys

## Context and Problem Statement

There is no staging fleet. Partial deploys and co-routed package skew (Keycloak,
Grafana) are the risk.

## Decision Outcome

A merge to `main` is a production deploy (GitLab deploy jobs, after
verify-from-attic). `gaming` stays manual. There is no separate staging
environment to promote from. Docs-only commits skip fill/deploy; a host whose
toplevel already matches `/run/current-system` is not switched
([2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md)).

### Consequences

Lint + inventory + Attic narinfo proof are the gates. `flake.nix` `co-routed-peers`
check exists because apps-1/apps-2 and obs-1/obs-2 can otherwise drift.
Rollback is per-host generations ([rollback.md](../runbooks/rollback.md)).
