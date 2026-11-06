---
status: accepted
date: 2026-11-03
---

# Decommission Attic and deploy from the builder store

## Context and Problem Statement

Production activation filled a monolithic Attic on `proxmox-dev`, then
copied each closure from that cache. The cache, its Postgres database,
and its Garage bucket existed only for deploys. Hosts could not use
`cache.nixos.org`. What replaces that path?

## Decision Drivers

* Attic is going away, including atticd, the NAR proxy, and the bucket
* `xcloud-postgres` is 1 GiB and `proxmox-observability` is 8 GiB; those
  VMs must not compile their own closures
* aarch64 still cannot be built with qemu on `proxmox-dev`
* `proxmox-applications-1` and `proxmox-applications-2` are mid-migration
  and must not be activated by this change

## Considered Options

* Keep Attic fill-then-exclusive
* Each host builds its own closure (`deploy-rs` `remoteBuild = true`)
* Build on the native builder and `nix copy` with `deploy-rs`

## Decision Outcome

Chosen option: "Build on the native builder and `nix copy` with
`deploy-rs`", because the small VMs already OOM when they build locally,
and the public cache is enough once the private cache is gone.

`proxmox-dev` builds `x86_64-linux`. `rpi4` builds `aarch64-linux` via
`scripts/run-on-rpi4.sh`. `remoteBuild` stays false and
`fastConnection` stays true, so the closure is copied from the builder
store. Deployed `nix.conf` lists `https://cache.nixos.org` (and the
Raspberry Pi cachix on `rpi4` only). The first switch passes those
substituters on the CLI, because the running `nix.conf` may still name
Attic.

`proxmox-applications-1` and `proxmox-applications-2` stay in the flake.
`fleet.inventory.deployPausedHosts` and `make deploy` skip them.

Attic is removed: the flake input, atticd, `attic-nar-proxy`, the
Postgres `attic` role wiring, and the Garage `attic` bucket bootstrap.
Activation does not drop the database or the bucket.

### Consequences

* Good, because there is no private NAR cache to keep healthy
* Good, because `magicRollback` applies to production activation
* Bad, because each deploy uploads the closure from the builder; hosts
  do not share a NAR cache
* Bad, because `proxmox-applications-1` and `proxmox-applications-2`
  keep the Attic substituter until a later deploy, and cannot `nix
  build` once atticd is stopped
* Bad, because the `attic` database and Garage bucket remain until an
  operator deletes them

## Validation

`make fmt` and `make lint`. `scripts/deploy-host.sh` exits if asked to
deploy a paused host. This record does not SSH-deploy.

## Pros and Cons of the Options

### Keep Attic fill-then-exclusive

* Good, because a populated cache avoids copying every NAR from the
  builder
* Bad, because the cache, its database, and its bucket stay in the
  critical path of every deploy

### Each host builds its own closure

* Good, because there is no central builder store to copy from
* Bad, because that OOM-killed nix-daemon on the cloud VMs, and the
  observability VM cannot compile Loki, Mimir, or Grafana on a miss

### Build on the native builder and nix-copy with deploy-rs

* Good, because the build stays on machines that already do it
* Good, because `cache.nixos.org` covers the substituted paths
* Bad, because a down builder blocks deploys of that architecture

## More Information

Operate from [deployments.md](../deployments.md). Supersedes the Attic
deploy, substituter, and placement records dated 2026-08-29 through
2026-09-18.


## Operator cleanup (Postgres) — done 2026-11-06

On `xcloud-postgres`, after a final dump (kept in
`/var/backups/decommission-2026-11-06/attic.dump`):

```sql
DROP DATABASE IF EXISTS attic;
DROP ROLE IF EXISTS attic;
```

The leftover `attic` ciphertext was removed with `sops unset` (nothing
read these keys), then `make check-secrets`:

| Host file | Keys deleted |
|-----------|----------------|
| `secrets/proxmox-dev/secrets.yaml` | `attic/env` |
| `secrets/xcloud-postgres/secrets.yaml` | `postgres/attic_password` |
