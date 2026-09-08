---
status: accepted
date: 2026-09-08
---

# GitLab deploys only hosts whose NixOS toplevel changed

## Context and Problem Statement

A Nix-relevant merge to `main` already skip-switched a host whose
`/run/current-system` matched the evaluated toplevel, but GitLab still
started every fill, verify, and deploy job. The runner allows four Docker
jobs; each x86 deploy boots `nixos/nix` and realizes `.#ci-tools`;
`fill-attic-rpi4` native-compiles on the Pi even when `rpi4` did not
change. How should CI decide which hosts to fill and switch?

## Decision Drivers

* Shared modules in `flake.nix` `commonModules` mean a file glob per host
  (`hosts/xcloud-caddy/**`) would miss lockfile and `config/` changes.
* Attic is the persistent store; job containers stay ephemeral
  ([2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md)).
* `gaming` stays manual. `rpi4` stays native and `allow_failure`.
* Merge to `main` still deploys
  ([2026-08-29-no-staging.md](2026-08-29-no-staging.md)).

## Considered Options

* Per-host GitLab `rules:changes` globs
* One sequential deploy job looping every host
* Eval toplevel outPaths vs a baseline revision; generate a child
  pipeline with only those hosts' jobs

## Decision Outcome

Chosen option: "Eval toplevel outPaths vs a baseline revision; generate
a child pipeline with only those hosts' jobs", because Nix store paths
are the closure identity, and omitting jobs is what frees runner slots.

`scripts/changed-hosts.sh` evals
`nixosConfigurations.<host>.config.system.build.toplevel` at `HEAD` and
at a baseline (one `nix eval --json`, including `rpi4`). Hosts whose
outPath differs are the work set. Baseline is `CI_COMMIT_BEFORE_SHA` on
`main`, `origin/main` on a branch, and every host for a web / `pipeline`
source, a missing baseline, or a failed baseline eval.

The parent pipeline runs `test` and `select-hosts`, then triggers a
child from `generated-pipeline.yml` (`strategy: depend`). The child
fills, narinfo-verifies, and deploys only that set. `ATTIC_HOSTS`
filters `attic_fill_hosts` and `verify-from-attic.sh`. Unset still means
all current-system hosts so local `make build` is unchanged. Skip-switch
in `deploy-from-attic.sh` remains the activation gate.

Do not use per-host file globs. Do not bind-mount the host `/nix` store
into jobs.

### Consequences

* Good, because a `services/gitlab.nix`-only merge fills and switches
  `proxmox-applications-2` and does not native-build `rpi4`.
* Good, because a `flake.lock` nixpkgs bump still fans out like today.
* Bad, because a changed host still substitutes its closure into the
  ephemeral job store in order to push new NARs. That is download cost,
  not a from-source rebuild, and not a full re-upload to Attic.
* Bad, because an operator rollback is not overwritten until that host's
  toplevel changes again or a web pipeline / `ATTIC_FORCE_SWITCH=1` runs.

## Validation

`make fmt` / `make lint`. Dry-run
`scripts/gitlab-gen-pipeline.sh` against a one-host
`changed-hosts.json`. After merge: parent shows `select-hosts` plus a
child with a subset of deploy jobs; skip-switch still logs `Skipping
$HOST` when live matches.

## More Information

[deployments.md](../deployments.md). Image, skip-switch, narinfo verify:
[2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md).
