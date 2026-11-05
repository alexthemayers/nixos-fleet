---
status: superseded by [2026-11-05-ci-lint-only.md](2026-11-05-ci-lint-only.md)
date: 2026-11-05
---

# GitLab is CI of record

## Context and Problem Statement

The repo has GitHub (public mirror / PRs) and GitLab (self-hosted, tailnet
runners). Only GitLab can SSH to fleet hosts.

## Decision Outcome

GitLab CI is authoritative: lint, format, inventory, and deploy on
`main`. GitHub `.github/workflows/lint.yml` is lint-only
and has no tailnet. Pipeline shape:
[2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md),
[2026-09-08-incremental-gitlab-deploys.md](2026-09-08-incremental-gitlab-deploys.md).

### Consequences

A green GitHub check is not a license to deploy. Operators use the same
scripts as GitLab (`make lint`, `make fmt-check`,
`scripts/deploy-host.sh`).
