# ADR: GitLab is CI of record

**Status:** accepted (2026-08-29)

## Context

The repo has GitHub (public mirror / PRs) and GitLab (self-hosted, tailnet
runners). Only GitLab can reach Attic and SSH to fleet hosts.

## Decision

GitLab CI is authoritative: lint, format, inventory, fill Attic, narinfo
proof, deploy on `main`. GitHub `.github/workflows/lint.yml` is lint-only
and has no tailnet. Pipeline shape:
[2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md).

## Consequences

A green GitHub check is not a license to deploy. Operators use the same
scripts as GitLab (`make lint`, `make fmt-check`, `make build`,
`make verify-from-attic`, `scripts/deploy-from-attic.sh`).
