# Attic

Attic is removed. Production deploys build on the native builder and
`nix copy` the closure with `deploy-rs`. Hosts substitute from
`cache.nixos.org`.

Decision: [2026-11-03-decommission-attic.md](../adr/2026-11-03-decommission-attic.md).
How to deploy: [deployments.md](../deployments.md).

Nix no longer declares the Postgres `attic` role/pool or the Garage
`bootstrap_s3 "attic"` path. On-disk data remains until the operator
cleans it up after atticd is stopped:

1. On `xcloud-postgres`: drop role/database `attic` (and any leftover
   `postgres/attic_password` ciphertext under `secrets/`).
2. On Garage: delete the `attic` bucket and key when nothing reads them.

`proxmox-applications-1` and `proxmox-applications-2` are in
`fleet.inventory.deployPausedHosts` / Makefile `DEPLOY_PAUSED`;
`make deploy` skips them. Their running `nix.conf` still names Attic
until a later migration deploy.
