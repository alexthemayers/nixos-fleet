---
status: accepted
date: 2026-08-31
---

# GitLab CI uses a Nix image, skip-switch, and narinfo verify

## Context and Problem Statement

Every GitLab job started from `debian:trixie-slim` and ran the Determinate
installer. `build-devshell` filled Attic but tests used `needs: []`, so they
never saw that store and still competed for the runner's 4 Docker slots.
`lint` / `format` / `check-inventory` were three installs. `fill-attic` built
hosts one at a time. `verify-from-attic` downloaded every x86 closure into an
ephemeral job that threw them away. Each deploy job installed Nix again, filled
that host again, and ran `switch-to-configuration` even when `/run/current-system`
already matched. Docs-only merges to `main` activated the fleet.

The fill-then-exclusive Attic contract and the unprivileged runner stay.

## Decision Outcome

1. **Job image is `nixos/nix`** (Docker Hub, pulled through
   `proxmox-applications-2:5000`). Empty `entrypoint` so GitLab's script runs.
   `.#ci-tools` (bash, make, openssh, python3, rsync) is realized in
   `before_script`. rpi4 proxy jobs stay on `debian:trixie-slim` and only SSH.
   Do not bind-mount the host `/nix` store into jobs.
2. **One `test` job** runs `make lint fmt-check check-inventory`. No
   `build-devshell`.
3. **`scripts/lint.sh`** is `nix flake check --all-systems --no-build`.
4. **`build.sh`** fills uncached current-system hosts in one `nix build`, then
   pushes each closure. `ATTIC_SKIP_IF_CACHED=1` still skips hosts already in
   Attic.
5. **`verify-from-attic.sh`** checks narinfos (`attic_closure_cached`). It does
   not download host NARs. Deploy copies them onto the target from Attic.
6. **`deploy-from-attic.sh`** compares
   `nixosConfigurations.<host>.config.system.build.toplevel` to
   `/run/current-system` and exits 0 if they match (`ATTIC_FORCE_SWITCH=1`
   overrides). GitLab sets `ATTIC_SKIP_FILL=1` after verify so deploy does not
   fill again. Operator runs without `ATTIC_SKIP_FILL` still fill-then-exclusive.
7. **Docs-only commits** skip fill, verify, and deploy (`rules:changes` on Nix,
   lockfile, scripts, secrets, SSH, CI YAML). Manual / `web` pipelines still
   run. `interruptible: true` on test/fill/verify. `resource_group` on fill
   (`attic-fill`, `attic-fill-rpi4`). Deploy is not interruptible.

### Consequences

A merge to `main` still deploys production, but only hosts whose toplevel
changed, and only when the change can affect a closure. Gaming stays manual.
NAR download happens at `nix copy --from` Attic onto the target, not in verify.
The first `nixos/nix` pull warms the Docker Hub pull-through cache on apps-2.

## More Information

Which hosts fill and deploy in GitLab:
[2026-09-08-incremental-gitlab-deploys.md](2026-09-08-incremental-gitlab-deploys.md).
