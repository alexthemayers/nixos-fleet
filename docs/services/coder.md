# Coder

Coder is **not running**. The builder is the Debian guest
`proxmox-dev` (inventory `proxmox-dev-debian`), which does not start it.
The Postgres role `coder` may still exist on `xcloud-postgres`.

The NixOS module `services/coder.nix` was removed. Do not recreate it
without a new ADR. Edge Caddy vhost history, if any, lives under
[caddy.md](caddy.md) and the edge ADRs.
