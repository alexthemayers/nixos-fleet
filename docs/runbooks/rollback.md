# Runbook: roll a host back

**Status:** current (2026-11-03). This is the reverse of a production
activation (`deploy-rs` `nix copy` + `switch-to-configuration`), not a
Postgres or GitLab restore. For those, see
[how-to-postgres-setup.md](../how-to-postgres-setup.md) and
[services/gitlab.md](../services/gitlab.md). `magicRollback` applies to
`make deploy` / `scripts/deploy-host.sh`.

## What a generation is

Every successful `switch-to-configuration switch` (what
[`scripts/deploy-host.sh`](../../scripts/deploy-host.sh) runs via
deploy-rs) adds a generation under
`/nix/var/nix/profiles/` on that host:

```
/nix/var/nix/profiles/system          # current
/nix/var/nix/profiles/system-42-link  # generation 42
```

List them:

```bash
ssh root@<host> nix-env --list-generations --profile /nix/var/nix/profiles/system
```

The current generation is also visible as `readlink /run/current-system`.

## Roll back one host

If the host still answers SSH, pick either form. They do the same thing: activate
the previous generation and make it current.

```bash
# Previous generation:
ssh root@<host> nixos-rebuild --rollback switch

# A specific generation, when you know the number:
ssh root@<host> /nix/var/nix/profiles/system-41-link/bin/switch-to-configuration switch
```

`nixos-rebuild --rollback` only walks back one step. If you need to skip a
broken generation, use the `system-N-link` form.

Do not combine a rollback with a new deploy from this repo in the same window.
The next `make deploy-host HOST=…` (or GitLab deploy) will push whatever
is in git and overwrite the rollback.

## `magicRollback`

`flake.nix` `mkNode` defaults `magicRollback = true` on every node.
Production activation is deploy-rs, so a failed SSH confirmation reverts
the generation. Use this runbook when you want a specific older
generation, or when SSH died before the confirmation.

If a host is ever set to `magicRollback = false`, a failed confirmation does
**not** revert. Recovery is then console-only (below). As of 2026-08-29 no node
opts out.

## If SSH is dead

1. **Proxmox guests** (`proxmox-*`): open the VM console in Proxmox and log in
   as root. Then run `nixos-rebuild --rollback switch` (or activate a known-good
   `system-N-link`) from that console.
2. **xcloud VMs** (`xcloud-caddy`, `xcloud-postgres`): the provider's serial /
   VNC console, same commands.

Host keys are pinned in `ssh/fleet_known_hosts`. A rollback does not change
them. If you regenerated a host key as part of the bad generation, follow
[split-shared-host-keys.md](split-shared-host-keys.md) rather than this
runbook.

## Reboot the fleet

`make reboot-all` iterates `CLOUD_HOSTS` only. It does **not** include
`gaming`. A reboot is not a rollback: the host comes back on the same
generation it left.

```bash
make reboot-all
# or one host:
ssh -o ConnectTimeout=3 root@<host> reboot
```

## What this runbook does not cover

- Restoring Postgres from `postgresqlBackup` dumps — [restore-postgres.md](restore-postgres.md).
- Restoring GitLab from `gitlab-backup` — [restore-gitlab.md](restore-gitlab.md).
- Rolling back a sops rotation. Secrets live in git; to undo a rotation, revert
  the secret file and redeploy, then confirm the consuming unit actually
  restarted (`restartUnits` is set on the secret-consuming services, but still
  verify).
