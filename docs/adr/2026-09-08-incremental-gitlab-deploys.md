---
status: superseded by [2026-11-05-ci-lint-only.md](2026-11-05-ci-lint-only.md)
date: 2026-11-05
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
at a baseline, **one host per `nix eval`** (including `rpi4`). A single
`mapAttrs` over every configuration OOM-kills the 12 GiB builder.
Hosts whose outPath differs are the work set. Baseline is
`CI_COMMIT_BEFORE_SHA` on `main`, `origin/main` on a branch, and every
host for a web / `pipeline` source, a missing baseline, or a failed
baseline eval.

The parent pipeline runs `test`, then `select-hosts` (`needs: test`).
Nix-heavy jobs share GitLab `resource_group: proxmox-dev-nix` so
`flake check`, select, and x86 deploys never overlap on `proxmox-dev`.
Then a child from `generated-pipeline.yml` (`strategy: depend`) deploys
only that set, except hosts in `fleet.inventory.deployPausedHosts`.
Skip-switch in `deploy-host.sh` remains the activation gate.

Do not use per-host file globs. Do not bind-mount the host `/nix` store
into jobs.

### Consequences

* Good, because a `services/gitlab.nix`-only merge selects
  `proxmox-applications-2` and does not native-build `rpi4`. That host
  is deploy-paused, so the child does not activate it.
* Good, because a `flake.lock` nixpkgs bump still deploys every host
  whose toplevel moved, one Nix eval at a time on the builder.
* Bad, because a changed host still builds in the ephemeral job store
  and `nix copy`s the closure to the target.
* Bad, because x86 deploys are serialized on `proxmox-dev-nix`. A
  lockfile bump takes longer wall time than four parallel deploys, on
  purpose: 12 GiB cannot hold two NixOS evals.
* Bad, because an operator rollback is not overwritten until that host's
  toplevel changes again or a web pipeline / `FORCE_SWITCH=1` runs.

## Validation

`make fmt` / `make lint`. Dry-run
`scripts/gitlab-gen-pipeline.sh` against a one-host
`changed-hosts.json`. After merge: parent shows `select-hosts` plus a
child with a subset of deploy jobs; skip-switch still logs `Skipping
$HOST` when live matches.

## More Information

[deployments.md](../deployments.md). Image, one test job, docs-only skip:
[2026-08-31-gitlab-ci-pipeline.md](2026-08-31-gitlab-ci-pipeline.md).
