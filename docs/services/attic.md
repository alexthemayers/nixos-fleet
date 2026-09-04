# Attic (Nix binary cache)

**Host:** `proxmox-dev` · **Module:** [services/attic.nix](../../services/attic.nix)

## Overview

Attic is the fleet's self-hosted Nix binary cache, and the **only** substituter
shipped on deployed hosts. Closures are **filled** here first (builders may
copy from `cache.nixos.org` if a NAR is missing), then copied onto targets
with `nix copy --from http://proxmox-dev:8080/attic`. After fill, realize and
activate use Attic only. Attic is an accepted SPOF for deploys.

The whole stack (atticd + `attic-nar-proxy`) runs on `proxmox-dev`. NAR chunks
live in the Garage `attic` bucket on the db nodes. Cache metadata lives in
Postgres (`attic` database) through PgBouncer.

## Networking

- **Port**: `8080` (TCP), open on `tailscale0` only. atticd itself listens on
  `127.0.0.1:8081`; `attic-nar-proxy` on `:8080` follows single-chunk 307s to
  Garage and returns **200**, which Nix requires of a substituter. Caddy cannot
  do this hop: it either fails to dial the Location URL or re-encodes the query
  string and breaks the Garage signature.
- **Load balanced** at `http://proxmox-lb:8080` to `proxmox-dev:8080`, health
  check on `/`.
- **Substituter URL**: `http://proxmox-dev:8080/attic` (the monolithic node,
  through attic-nar-proxy). Deploy copies use this URL
  (`attic_copy_closure_to_ssh`). `http://proxmox-lb:8080/attic` is the
  load-balanced hop; Caddy can still truncate multi-chunk NARs
  (`Transferred a partial file`), so hosts and deploys talk to proxmox-dev.
  There is **no** public vhost.
- **Postgres**: `ATTIC_SERVER_DATABASE_URL` in `attic/env` must use
  **PgBouncer** `xcloud-postgres:5432`. Raw Postgres `:5433` is firewalled on
  `tailscale0`. sqlx needs a session, so PgBouncer's `attic` database is
  `pool_mode=session pool_size=20 max_db_connections=20`.

## Storage

S3-compatible storage in Garage at `http://proxmox-lb:3902`. Presigned URLs
use that endpoint. Clients never see those URLs: `attic-nar-proxy` on `:8080`
follows the 307 and returns the object.

```toml
[storage]
type = "s3"
bucket = "attic"
endpoint = "http://proxmox-lb:3902"
region = "garage"
```

Chunking is configured for deduplication (avg 256 KiB, min 16 KiB, max 1 MiB,
with a 64 KiB NAR size threshold below which files are stored whole).

## Modes: exactly one monolithic node

`atticd` runs in one of two roles, selected per host by
`fleet.services.attic.mode` (which sets the upstream `services.atticd.mode`):

| Mode          | Serves API | Runs GC and background jobs |
|---------------|------------|-----------------------------|
| `monolithic`  | yes        | **yes**                     |
| `api-server`  | yes        | no                          |

Exactly one host in the fleet must be `monolithic`, because that is the
instance that garbage-collects the cache. Today that is `proxmox-dev`
([attic-on-proxmox-dev ADR](../adr/2026-09-04-attic-on-proxmox-dev.md)):

```nix
# hosts/proxmox-dev/configuration.nix
fleet.services.attic.mode = "monolithic";
```

`api-server` is the default, so any new node that imports the module is safe
by default.

> **Why this is an option rather than a hostname check.** This used to be
> decided inside the module by comparing `networking.hostName` against a
> literal hostname. Renaming or replacing that host would have silently
> demoted every instance to `api-server`, leaving nothing running garbage
> collection — the cache would have grown until Garage filled up, with no
> error anywhere to indicate why.

If you move the monolithic role, move it explicitly, and confirm afterwards
that exactly one host has it:

```bash
nix eval --raw ".#nixosConfigurations.proxmox-dev.config.fleet.services.attic.mode"
```

## Push and deploy

`ATTIC_TOKEN` is required for `make build` and `make deploy-from-attic HOST=…`.
The token is a JWT from `atticadm make-token` (pull + push on the `attic`
cache). CI stores it as a masked variable. Mint tokens on `proxmox-dev`.

```bash
export ATTIC_TOKEN=…
make build                          # build every current-system host, attic push
make deploy-from-attic HOST=proxmox-dev
```

`scripts/deploy-from-attic.sh` fills the host and operator tooling with builder
substituters if a path is missing, pushes the closure with `attic_push_closure`
(`ATTIC_PUSH_JOBS`, default 8; Garage is LMDB) and
`--ignore-upstream-cache-filter` (otherwise Attic skips paths already on
cache.nixos.org and `nix copy --from` Attic 404s), proves the closure is in
Attic, then copies onto the host from Attic only (`attic_copy_closure_to_ssh`,
`narinfo-cache-negative-ttl 0` so a one-off 307 does not stick for an hour)
and `switch-to-configuration`. If `/run/current-system` already matches the
host toplevel, it skips the switch (`ATTIC_FORCE_SWITCH=1` to override). After
fill there is no `cache.nixos.org`. The target does not receive the closure
from the builder store. Scripts realize `.#attic` themselves so they do not
need `nix develop` on an Attic-only builder. Deploy `proxmox-dev` first when
the Attic host changes; Garage still deploys db-1 and db-2 first
([garage-lmdb runbook](../runbooks/garage-lmdb.md)).

`atticd` waits up to 600s for PgBouncer on `xcloud-postgres:5432` and for
Garage on `proxmox-db-1:3902` plus `proxmox-lb:3902` (`fleet.waitForHost`) so
a random boot order does not leave the cache crashing on a missing DB or S3
endpoint.

First switch after moving the stack onto `proxmox-dev`: fill and prove
against the previous generation
(`ATTIC_ENDPOINT=http://proxmox-db-1:8080`) while db-1 still runs atticd,
then switch `proxmox-dev` locally. After atticd answers on
`proxmox-dev:8080`, deploy the rest (new substituter URL) and only then
switch the db nodes (Attic dropped).

## Secrets

- **`attic/env`**: rendered by sops as an `EnvironmentFile` owned by the
  `atticd` user with mode `0440`. It carries the server token signing key,
  `ATTIC_SERVER_DATABASE_URL` (PgBouncer `:5432`), and the Garage S3
  credentials. Stored in `secrets/proxmox-dev/`.
