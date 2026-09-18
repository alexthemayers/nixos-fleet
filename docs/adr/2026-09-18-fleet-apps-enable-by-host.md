---
status: accepted
date: 2026-09-18
---

# App enablement follows `fleet.apps`, not host files

## Context and Problem Statement

Serving host, listen port, and public URL already live in
[`fleet/apps/`](../../fleet/apps/). The flake still listed every service
module per `nixosConfiguration`, and host files still held restart policy,
Garage NFS, Attic mode, Redis enable, and qBittorrent sysctls. Which host
runs an app was written three times.

## Decision Drivers

* One data file per app is the place to change host or port
* Importing GitLab on `rpi4` would eval aarch64 packages we do not run
* Host files stay hardware, disk, and hub RAM caps

## Considered Options

* Import every `services/*.nix` on every host and `mkIf` on hostname
* Keep the per-host lists in `flake.nix` and only move knobs out of `hosts/`
* `flake.nix` imports `module` only for `host` plus `extraHosts`

## Decision Outcome

Chosen option: "`flake.nix` imports `module` only for `host` plus
`extraHosts`", because that is the registry enable map without evaluating
Immich or GitLab on the Pi.

[`config/fleet-app-imports.nix`](../../config/fleet-app-imports.nix) reads
the data files (not `config.fleet.apps`, which would recurse) and returns
module paths. Each service still `mkIf`s `fleet.appOnThisHost.<name>` so a
wrong import does not declare that host's sops secrets. Vaultwarden sets
`extraHosts = [ "rpi4" ]` for the Syncthing replica; the edge still points
only at apps-1
([vaultwarden-no-edge-failover](2026-09-06-vaultwarden-no-edge-failover.md)).

`hosts/<name>/configuration.nix` does not enable applications. Remaining
flake imports are hub modules with no registry entry yet (Postgres,
Prometheus, Loki, Mimir, GitLab Runner, pull-through caches).

### Consequences

* Good, because adding a public app is `fleet/apps/<name>.nix` with `module`
* Good, because rpi4 does not import x86-only app modules
* Bad, because hub services still appear in `flake.nix` until they get
  registry entries
* Bad, because renaming a host requires matching `fleet.apps.*.host`

## Validation

`nix flake check --all-systems --no-build`. `fleet.apps` assertions cover
unknown hosts, duplicate vhosts, unknown `extraHosts`, missing docs/module
paths, a second Attic import, a non-caddy edge listener, and Keycloak
`edge.auth`.

## Pros and Cons of the Options

### Import every module on every host

* Good, because flake lists shrink to hardware only
* Bad, because aarch64 eval of GitLab/Immich/Coder amd64

### Keep flake lists; only empty host files

* Good, because import set stays explicit
* Bad, because `host` in the registry still duplicates the flake list

### Import `module` on `host` plus `extraHosts`

* Good, because one file is the enable map
* Good, because eval stays per-host
* Bad, because `flake.nix` still lists hub modules

## More Information

Schema: [custom-options.md](../custom-options.md#app-registry-fleetapps).
How to add a vhost: [how-to-reverse-proxy.md](../how-to-reverse-proxy.md).
