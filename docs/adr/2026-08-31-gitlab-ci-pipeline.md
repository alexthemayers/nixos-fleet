---
status: superseded by [2026-11-05-ci-lint-only.md](2026-11-05-ci-lint-only.md)
date: 2026-11-05
---

# GitLab CI uses a Nix image, one test job, and docs-only skip

## Context and Problem Statement

Every GitLab job started from `debian:trixie-slim` and ran the Determinate
installer. `build-devshell` filled Attic but tests used `needs: []`, so they
never saw that store and still competed for the runner's 4 Docker slots.
`lint` / `format` / `check-inventory` were three installs. `fill-attic` built
hosts one at a time. `verify-from-attic` downloaded every x86 closure into an
ephemeral job that threw them away. Each deploy job installed Nix again, filled
that host again, and ran `switch-to-configuration` even when `/run/current-system`
already matched. Docs-only merges to `main` activated the fleet.

The unprivileged runner stays. Deploy no longer fills Attic
([2026-11-03-decommission-attic.md](2026-11-03-decommission-attic.md)).

## Decision Outcome

1. **Job image is `nixos/nix`** (Docker Hub, pulled through
   `proxmox-applications-2:5000`). Empty `entrypoint` so GitLab's script runs.
   `.#ci-tools` (bash, make, openssh, python3, rsync) is realized in
   `before_script`. rpi4 proxy jobs stay on `debian:trixie-slim` and only SSH.
   Do not bind-mount the host `/nix` store into jobs.
2. **One `test` job** runs `make lint fmt-check check-inventory`. No
   `build-devshell`.
3. **`scripts/lint.sh`** is `nix flake check --all-systems --no-build`.
4. **`deploy-host.sh`** compares
   `nixosConfigurations.<host>.config.system.build.toplevel` to
   `/run/current-system` and exits 0 if they match (`FORCE_SWITCH=1`
   overrides). It then `nix copy`s from the builder store with `deploy-rs`.
   x86 deploy jobs share `resource_group: proxmox-dev-nix`.
5. **Docs-only commits** skip select and deploy (`rules:changes` on Nix,
   lockfile, scripts, secrets, SSH, CI YAML). Manual / `web` pipelines still
   run. `interruptible: true` on test and select. Deploy is not interruptible.

### Consequences

A merge to `main` still deploys production, but only hosts whose toplevel
changed, and only when the change can affect a closure. Gaming stays manual.
The closure is `nix copy`d from the builder store. The first `nixos/nix`
pull warms the Docker Hub pull-through cache on apps-2.

## More Information

Which hosts deploy in GitLab:
[2026-09-08-incremental-gitlab-deploys.md](2026-09-08-incremental-gitlab-deploys.md).
