---
status: accepted
date: 2026-11-05
---

# GitLab CI is lint and inventory only; deploy is operator-driven

## Context and Problem Statement

GitLab CI built host closures and deployed changed hosts on merge to
`main` (child pipeline from toplevel outPath diffs). That coupled every
merge to production activation, needed deploy SSH in CI, and kept select
and deploy jobs on the 12 GiB builder. Deploy already works from
`proxmox-dev` / `rpi4` via `deploy-host.sh`. Ansible had no CI gate.

## Decision Drivers

* Deploy must not run from CI
* CI must not build NixOS host toplevels
* Nix and Ansible both need an offline gate
* No staging fleet

## Considered Options

* Keep incremental GitLab deploys on `main`
* CI lint/fmt/inventory/ansible-lint only; operator deploys
* Drop GitLab CI entirely; rely on GitHub lint

## Decision Outcome

Chosen option: "CI lint/fmt/inventory/ansible-lint only; operator
deploys", because production activation stays an explicit operator
action and the gate still covers Nix and both Ansible trees.

1. **GitLab** runs one `test` job:
   `make lint fmt-check check-inventory ansible-lint`.
   Image stays `nixos/nix` plus `.#ci-tools` (now includes `ansible` and
   `ansible-lint`). `resource_group: proxmox-dev-nix` stays. The gate
   always runs (including docs-only commits).
2. **No select, child pipeline, or deploy jobs.** Delete
   `ci/jobs.yml`, `scripts/gitlab-select-hosts.sh`, and
   `scripts/gitlab-gen-pipeline.sh`. Keep
   `scripts/changed-hosts.sh` for local "what would change" evals.
3. **`make lint` stays Nix-only** (`flake check --all-systems
   --no-build`). Ansible is `make ansible-lint` (both
   `ansible/proxmox.yml` and `fleet.debian_guest` `site.yml`, Galaxy
   deps into a disposable path, `--offline`, no vault).
4. **Deploy** is operator-only: `make deploy*` /
   `scripts/deploy-host.sh` on `proxmox-dev`, rpi4 via
   `run-on-rpi4.sh`. Merge to `main` does not activate hosts.
5. **GitHub** `.github/workflows/lint.yml` mirrors the GitLab gate
   (lint, fmt-check, check-inventory, ansible-lint, plus later
   check-obs-config and check-secrets-keys). GitLab remains CI of
   record.
6. **No staging.** There is still no staging fleet; promotion is
   merge then an intentional local deploy.

Supersedes
[2026-08-29-gitlab-ci-of-record.md](2026-08-29-gitlab-ci-of-record.md),
[2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md),
[2026-09-08-incremental-gitlab-deploys.md](2026-09-08-incremental-gitlab-deploys.md),
and
[2026-08-29-no-staging.md](2026-08-29-no-staging.md).

### Consequences

* Good, because merge cannot switch production by itself
* Good, because Ansible and Nix share one gate
* Bad, because a green pipeline is not a deploy; the operator must run
  activate on purpose
* Neutral, because `SSH_PRIVATE_KEY` is unused in CI and can be removed
  from GitLab variables

## Validation

`.gitlab-ci.yml` has a single `test` job and no `trigger` / deploy
stages. `make ansible-lint` and `make lint` pass locally and in CI.

## More Information

[deployments.md](../deployments.md),
[gitlab-runner.md](../services/gitlab-runner.md).
