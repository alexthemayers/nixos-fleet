# Agent notes for nixos-fleet

This is a NixOS flake for a homelab plus two cloud VMs. GitLab is CI of record.
Decisions live in [docs/adr/](docs/adr/README.md). [docs/fleet-audit.md](docs/fleet-audit.md)
is an investigation log, not the operational spec.

**Do not commit or push.** The operator commits. Do not `git commit`, `git push`,
`--amend`, or skip hooks unless the user explicitly asks in that turn. When
you do commit, do not add `--trailer` or a `Co-authored-by: Cursor
<cursoragent@cursor.com>` line. The operator is the only author.

**Docs and ADRs are part of the change.** If you change behaviour, topology,
deploy path, substituters, auth, or a freeze: update the matching
`docs/services/` / runbook / README, and add or amend an ADR under `docs/adr/`
(ISO date + slug, one decision). Do not leave the tree contradicting
`docs/standards.md` or the README. Do not treat `fleet-audit.md` as something
to “fix” into current truth.

Read order when touching a service: this file → [docs/adr/README.md](docs/adr/README.md)
→ [docs/deployments.md](docs/deployments.md) → the service or host doc you are
changing.

## How to iterate

```bash
make fmt              # nix fmt
make fmt-check        # nix fmt -- --ci (same as GitLab format)
make lint             # flake eval + nix flake check --no-build
make check-inventory  # Makefile hosts vs config/fleet-inventory.nix
make check-secrets    # local only; needs the operator age key
make build            # ATTIC_TOKEN; build currentSystem hosts, attic push
make verify-from-attic  # ATTIC_TOKEN; realize every host from Attic only
make deploy-from-attic HOST=proxmox-dev
```

Production activation fills Attic (public substituters only if a NAR is
missing), then copies the closure from Attic and `switch-to-configuration`.
After fill, realize / copy / `nix develop` use Attic only. `make deploy-rs`
is the fallback (magicRollback, copy from the builder store).

`gaming` is a production Attic target (`make deploy-gaming`). `make reboot-all`
skips it so a fleet reboot does not take down a desktop. **Every deploy
(including `gaming`) runs from `proxmox-dev`.** Do not build or
`deploy-from-attic` on `gaming` or on the laptop.

## Operator machine

Edits land on the Darwin checkout. **All Attic builds and deploys run on
`root@proxmox-dev`.** Do not `make deploy` / `deploy-from-attic` from the
laptop store or from `gaming`. Never print `ATTIC_TOKEN`.

```bash
rsync -az --delete --exclude='.git/' --exclude='result' --exclude='.direnv/' \
  /Users/alex/code/nixos-fleet/ root@proxmox-dev:/root/nixos-fleet-deploy/
ssh root@proxmox-dev 'bash -s' << 'EOF'
set -euo pipefail
export ATTIC_TOKEN=$(cat /root/.attic-token)
export ATTIC_CACHE_URL="http://proxmox-db-1:8080/attic"
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
cd /root/nixos-fleet-deploy
# Token: export ATTIC_TOKEN=$(cat /root/.attic-token) or leave it in that file;
# deploy-from-attic.sh will not start without one.
./scripts/deploy-from-attic.sh <host>
EOF
```

`--exclude='.git/'` means the copy is a path flake: every file on disk is
visible (including untracked). A `nix` eval **in this git checkout** only sees
tracked files — `git add` new Nix/Go/Python that a module references or lint
fails.

## Scope a change

Docs-only: no deploy. Garage metadata / Attic push concurrency: `proxmox-db-1`
and `proxmox-db-2` first ([docs/runbooks/garage-lmdb.md](docs/runbooks/garage-lmdb.md)),
then fill. Mimir / ntfy / Prometheus / Grafana: `proxmox-observability-1`
and `-2` only. Edge Caddy / Keycloak `/admin` CIDR: `xcloud-caddy`. Do not
`make deploy` the fleet for one service.

`flake.nix` `co-routed-peers` requires matching package versions on apps-1/apps-2
(Keycloak) and obs-1/obs-2 (Grafana, Loki, Mimir, ntfy). Deploy both peers of a
pair.

## After switch

`restartIfChanged = false` on Mimir, Grafana, Loki, ntfy (and similar). A
successful switch can leave the old process on the old config. Restart the
unit you changed and read the journal for `error parsing config` / exit 1
before calling it done. Invalid Mimir YAML keys (`bucket_lookup_type =
"path-style"`, `compactor.partial_block_deletion_delay`) crash-loop the
daemon; the valid forms are `path` and `limits.compactor_partial_block_deletion_delay`.

`nixos-rebuild --rollback` fails here (`nixos-config` is not on `NIX_PATH`).
Use `/nix/var/nix/profiles/system-N-link/bin/switch-to-configuration switch`.
See [docs/runbooks/rollback.md](docs/runbooks/rollback.md).

## CI vs local

| | Local (always `root@proxmox-dev`) | GitLab |
|---|---|---|
| Nix | already installed | Determinate installer in the job image |
| `ATTIC_TOKEN` | `/root/.attic-token` or env | CI variable |
| SSH | operator keys + `ssh/fleet_known_hosts` | `SSH_PRIVATE_KEY` CI variable |
| Fill | `make build` (hosts + `.#attic` + devShell) | `fill-attic` with `ATTIC_SKIP_IF_CACHED=1` and `ATTIC_BUILD_ALL_SYSTEMS=1` |
| Prove | `make verify-from-attic` | `verify-from-attic` job, `needs: fill-attic` |
| Deploy | `scripts/deploy-from-attic.sh` (fill, then exclusive) | same script; `needs: verify-from-attic`; `gaming` is manual |

Test jobs (`lint`, `format`, `check-inventory`) use `needs: []` so they do not
wait on `ATTIC_TOKEN`. GitHub Actions is lint-only and has no tailnet.

## Scripts

Do not put tokens in git. Env vars only. Never print `ATTIC_TOKEN`. Scripts
load `/root/.attic-token` when the env is unset; they refuse to start a fill
or deploy if both are missing.

| Script | Make target | Notes |
|---|---|---|
| [scripts/attic-common.sh](scripts/attic-common.sh) | (sourced) | fill vs exclusive helpers; `ATTIC_PUSH_JOBS`, `ATTIC_SKIP_IF_CACHED` |
| [scripts/lint.sh](scripts/lint.sh) | `make lint` | |
| [scripts/check-inventory.sh](scripts/check-inventory.sh) | `make check-inventory` | needs `python3` (in the flake devShell) |
| [scripts/check-secrets.sh](scripts/check-secrets.sh) | `make check-secrets` | age key; **not CI** |
| [scripts/build.sh](scripts/build.sh) | `make build` | fill only; `ATTIC_SKIP_IF_CACHED=1`, `ATTIC_BUILD_ALL_SYSTEMS=1`, `ATTIC_TOOLING_ONLY=1` |
| [scripts/verify-from-attic.sh](scripts/verify-from-attic.sh) | `make verify-from-attic` | substituter **only** `http://proxmox-db-1:8080/attic` |
| [scripts/deploy-from-attic.sh](scripts/deploy-from-attic.sh) | `make deploy-from-attic HOST=` | fill, then exclusive copy; `ATTIC_COPY_FROM_BUILDER=1` hatch |
| [scripts/nix-develop.sh](scripts/nix-develop.sh) | | fill the shell, then Attic-only `nix develop` when `ATTIC_TOKEN` is set |
| [scripts/attic-push.sh](scripts/attic-push.sh) | | batched push; used if you already have a store path |
| [scripts/update-known-hosts.sh](scripts/update-known-hosts.sh) | `make update-known-hosts` | from a trusted workstation `known_hosts` |

`make edit-secrets HOST=` / `make updatekeys` for sops. Ansible
(`make deploy-proxmox-host`) is not Nix; see
[docs/services/proxmox-host.md](docs/services/proxmox-host.md) and landmines.

## Landmines

- **Do not `chown` Garage meta to `garage`.** Idmapped mounts show
  `nobody:nogroup`.
- **Fix the Garage cluster, do not pin S3 clients.** Attic, Mimir, and Loki
  talk to Garage at `proxmox-lb:3902` (round-robin db-1/db-2). A 200 on one
  node and 404 on the other is split sqlite metadata. Repair that so
  round-robin is safe. Do not hide it by pinning clients at
  `proxmox-db-1:3902`. See
  [docs/runbooks/garage-metadata-resync.md](docs/runbooks/garage-metadata-resync.md)
  and [docs/adr/2026-08-30-garage-s3-lb.md](docs/adr/2026-08-30-garage-s3-lb.md).
- **Empty+`garage repair -a --yes tables` is a no-op if merkle is corrupt**
  (`Messagepack decode error`, stuck `MklTodo`). Rebuild merkle on the
  source node first (empty `merkle_tree`, enqueue `merkle_todo` as
  blake2b-512[:32] of each item, skip keys shorter than 32 bytes), wait
  until `MklTodo` drains, then table-repair onto the empty peer. Hand-rolled
  4-byte todo values coredump (`merkle.rs` `Hash::try_from`).
- **Do not `garage repair blocks` on this sqlite cluster.** It panicked in
  `RepairWorker` and coredumped db-1. Table repair only.
- **Deploy `proxmox-db-1` and `proxmox-db-2` before the first parallel fill.**
  Garage must already be LMDB. Until then, `ATTIC_PUSH_JOBS=1
  ATTIC_PUSH_BATCH_SIZE=12`. See
  [docs/runbooks/garage-lmdb.md](docs/runbooks/garage-lmdb.md).
- **Do not `nix-shell -p sqlite` on Attic-only hosts** (no cache.nixos.org).
- Substituters on deployed hosts are **db-1 `:8080`**, not the LB. Caddy on
  `proxmox-lb:8080` can truncate multi-chunk **NARs**. That is not Garage
  replication; S3 for Attic/Mimir/Loki still goes through `proxmox-lb:3902`.
- `attic-nar-proxy` follows Garage 307s with GET (Nix HEADs would 403).
- Nix negative-caches failed narinfos (`narinfo-cache-negative-ttl 0` on copy).
- `fleet.waitForHost` is a TCP probe with timeout; do not busy-wait in
  service scripts.
- Ansible vault password at `ansible/.vault_pass.txt` is **local-only**
  (gitignored), out of band from Nix/sops. Do not commit it and do not copy
  that pattern into flake secrets. See
  [docs/adr/2026-08-31-proxmox-ansible.md](docs/adr/2026-08-31-proxmox-ansible.md).
- Keycloak `/admin` requires a **tailnet source IP** at the edge, not merely
  Tailscale-up. See the README and
  [docs/services/keycloak.md](docs/services/keycloak.md#accessing-the-admin-console).

## Do not “fix”

These are accepted decisions. Do not flip them in a drive-by:

- WAF stays DetectionOnly ([docs/adr/2026-08-29-waf-detection-only.md](docs/adr/2026-08-29-waf-detection-only.md))
- oauth2-proxy is per-vhost, not fleet-wide
- One Attic `monolithic` node (`proxmox-db-1` only)
- Deployed hosts: Attic only, `http://proxmox-db-1:8080/attic` — no `cache.nixos.org`
- Fill may use `cache.nixos.org`; after fill, realize/copy/`nix develop` do not
  ([docs/adr/2026-08-30-attic-fill-then-exclusive.md](docs/adr/2026-08-30-attic-fill-then-exclusive.md))
- No staging; merge to `main` deploys
- Four hubs are SPOFs: `xcloud-postgres`, `xcloud-caddy`, `proxmox-lb`,
  `truenas-scale`

Do not document the fleet as blocking-WAF HA with unified forward-auth.

## Inventory and secrets

Adding a host: `Makefile` lists, `config/fleet-inventory.nix`,
`hosts/<name>/`, `secrets/<name>/secrets.yaml`, `ssh/fleet_known_hosts`,
flake `nixosConfigurations`. Then `make check-inventory` and
`make edit-secrets HOST=<name>` / `make updatekeys`.

Per-host sops files. No shared secret file. Inject via `sops.templates` +
systemd `EnvironmentFile` or `$__file{}` / runtime read. Never write a
password into the Nix store (`initialAdminPassword` and friends).
`make check-secrets` is local (age key); CI only eval-checks that declared
secrets exist.

## Hubs (accepted SPOFs)

`xcloud-postgres`, `xcloud-caddy`, `proxmox-lb`, `truenas-scale`. See
[docs/adr/2026-08-29-four-hubs.md](docs/adr/2026-08-29-four-hubs.md).

Service docs: [docs/](docs/). Custom options: [docs/custom-options.md](docs/custom-options.md).
