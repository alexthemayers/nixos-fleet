# Runbook: Attic ghost narinfos after an empty Garage

atticd's Postgres still has object rows after Garage is a new empty
cluster. atticd then serves a narinfo 200 whose NAR is missing or is a
Garage `NoSuchKey` body. Nix does not treat that as a substituter miss.
`attic push` skips the path as already cached.

> Warnings
>
> - Truncate **object / nar / chunk / chunkref** only. Keep the `cache`
>   row so the signing key and cache name stay.
> - Fill with `ATTIC_FILL_PUBLIC_ONLY=1` so realize does not retry the
>   empty cache.
> - Do not print `ATTIC_TOKEN`. Substituters stay
>   `http://proxmox-dev:8080/attic`.

## Repair

On `proxmox-dev`, then Postgres:

```bash
systemctl stop atticd
ssh root@xcloud-postgres \
  "sudo -u postgres psql -p 5433 -d attic -v ON_ERROR_STOP=1 \
   -c 'TRUNCATE TABLE chunkref, object, nar, chunk;'"
systemctl start atticd attic-nar-proxy
```

A known-bad hash must 404:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/attic/<store-hash>.narinfo
```

Refill current-system hosts (skip `gaming` if that machine is off).
On `proxmox-dev`, push through atticd on loopback `:8081`. The
nar-proxy on `:8080` times out `linux-firmware` (~800 MiB) at
`/_api/v1/upload-path` (connection timed out). Substituters stay
`http://proxmox-dev:8080/attic`. One job, smaller batches. Do not
run `deploy-from-attic.sh` during this refill.

```bash
export ATTIC_FILL_PUBLIC_ONLY=1
export ATTIC_ENDPOINT=http://127.0.0.1:8081
export ATTIC_CACHE_URL=http://127.0.0.1:8081/attic
export ATTIC_PUSH_JOBS=1
export ATTIC_PUSH_BATCH_SIZE=8
./scripts/build.sh
# or attic_fill_installable per host from scripts/attic-common.sh
```

If `attic push` returns `Bad NAR Hash or Size`, the local store
path is corrupt (`nix-store --verify-path` will say it was
modified). Repair from the public cache only — Attic-first
`repair-path` retries the empty NAR:

```bash
nix-store --repair-path \
  --option substituters "https://cache.nixos.org" \
  --option extra-substituters "" \
  --option trusted-public-keys \
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
  /nix/store/<hash>-<name>
```

Prove exclusive realize from Attic, then deploy without
`ATTIC_COPY_FROM_BUILDER`.
