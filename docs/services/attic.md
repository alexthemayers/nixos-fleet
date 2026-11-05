# Attic

Attic is removed. Production deploys build on the native builder and
`nix copy` the closure with `deploy-rs`. Hosts substitute from
`cache.nixos.org`.

Decision: [2026-11-03-decommission-attic.md](../adr/2026-11-03-decommission-attic.md).
How to deploy: [deployments.md](../deployments.md).

The Postgres `attic` database and the Garage `attic` bucket are not
dropped by activation. After `proxmox-dev` has switched off atticd, the
operator may drop that role and database on `xcloud-postgres` and delete
the Garage bucket. `proxmox-applications-1` and `proxmox-applications-2`
are not activated by this change; their running `nix.conf` still names
Attic until a later migration deploy.
