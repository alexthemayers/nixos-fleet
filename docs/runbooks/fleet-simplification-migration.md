# Runbook: start the fleet simplification migration

Executes [Phase 0](../fleet-simplification-plan.md#phase-0--stabilise-change-nothing-structural)
of the fleet simplification plan and stages
[Phase 1](../fleet-simplification-plan.md#phase-1--break-the-circular-storage-dependency).
Read the plan first; this is the "how", not the "why".

> Warnings
>
> - **There is currently no backup or snapshot safety net for any of the nine
>   on-prem guests.** No Proxmox `vzdump` job exists (`/etc/pve/jobs.cfg` is
>   absent, `/var/lib/vz/dump/` and the NFS `dump/` directory are both empty).
>   No ZFS snapshot exists on TrueNAS for any dataset
>   (`zfs list -t snapshot` returns nothing) and no periodic snapshot task is
>   configured. The qcow2 files on `truenas-storage` are the **only** copy of
>   every VM. Step 1 below fixes the cheapest part of this before anything
>   else happens.
> - **`rpi4` has been offline for 17+ hours** (`tx 8424 rx 0` in `tailscale
>   status`), not a blip. Today's `postgresqlBackup.service` run on
>   `xcloud-postgres` and today's `gitlab-backup` on `proxmox-applications-2`
>   both produced a fresh dump but **failed to ship it off-host**. Both
>   dumps currently exist as a single copy on the VM that already owns the
>   live data.
> - **`proxmox-applications-2`'s root disk is at 78% used.** This is the same
>   host and the same failure mode as the closed incident in
>   [`todo-deviations.md`](../todo-deviations.md) (backups accumulating
>   because the offsite sync target was unreachable). Do not let this run
>   again unattended.
> - **[`restore-postgres.md`](restore-postgres.md) and
>   [`restore-gitlab.md`](restore-gitlab.md) are both marked "not
>   drill-tested."** Do not assume a dump restores cleanly; this runbook does
>   not test that either, but it does get a second copy of the dumps to
>   somewhere durable, which is a precondition for ever testing it.
> - Do not run any step in "Break the storage dependency" (Phase 1 execution)
>   until the hardware in Step 6 has arrived. There is nowhere to move a disk
>   to yet.
> - Every `qm disk move` command below omits `--delete`. Proxmox's default is
>   to keep the source disk as `unusedN` on the VM after a successful copy.
>   Do not add `--delete` until Step 12 (post-verification cleanup).

## What "safe" means for this migration

Three different risks, three different mitigations:

| Risk | Mitigation | Where |
|------|-----------|-------|
| Fat-fingered command destroys a live VM disk before you've changed anything | Blanket ZFS snapshot of the whole `storage-pool` dataset | Step 1 |
| A disk move goes wrong mid-copy | `qm disk move` without `--delete`; source stays as `unusedN` until verified | Steps 9–12 |
| The hypervisor's one NVMe dies during or after the migration | Independent, verified, offsite copies of the things that are not otherwise reconstructible (Postgres dump, GitLab backup, sops secrets, this git repo) | Steps 2–5 |

VM root disks themselves are **not** independently backed up by this runbook
beyond the Step 1 snapshot. They do not need to be: every NixOS host rebuilds
from this flake. What cannot be rebuilt from git is application data
(Postgres, GitLab repos/registry, Vaultwarden, media/photos on TrueNAS) —
that is what Steps 2–5 protect.

## Pre-flight: the safety net (do this before anything else)

### Step 1 — Snapshot every VM disk right now

This is one command, costs only metadata today, and is the difference between
"redeployable in five minutes" and "gone" if any later step in this runbook
goes wrong. Run it from the hypervisor before touching anything:

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 30 -- \
  /usr/sbin/zfs snapshot ssd/proxmox/storage-pool@pre-migration-2026-09-07'
```

Verify it landed:

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 30 -- \
  /usr/sbin/zfs list -t snapshot -o name,used,creation ssd/proxmox/storage-pool'
```

This is **crash-consistent, not application-consistent** — it is the
equivalent of a power cut, taken while every VM is running. That is
sufficient for "undo my last command," which is its only job here. It is not
a substitute for the application-level backups in Steps 2–4, and it does not
protect against a `truenas-scale` failure or the `ssd` pool itself failing
(same-box, same-pool, same-limitations as the Garage RF=2 finding in the
plan).

Take a fresh one before each of Steps 9–12 (moving a specific VM's disk), so
a bad move only costs you that VM's progress:

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 30 -- \
  /usr/sbin/zfs snapshot ssd/proxmox/storage-pool@pre-move-<hostname>'
```

Rollback, if ever needed (**stop the affected VM first**, this reverts the
whole dataset that every VM's disk lives in):

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 60 -- \
  /usr/sbin/zfs rollback ssd/proxmox/storage-pool@<snapshot-name>'
```

### Step 2 — Get `rpi4` back, or route around it

Pick one; do not skip both:

- **Fix it.** It is the designated offsite target for Postgres and GitLab
  backups and the Vaultwarden replica. Physically check power/USB/network.
- **Reroute, if it stays down past today.** Point
  `postgresqlBackup`'s rsync target and `gitlab-backup-sync` somewhere else
  temporarily. `truenas-scale` cannot be that target — it has no `sshd`
  running (connections to port 22 are refused) — so this reroutes to
  `proxmox-dev` instead, over the same shared `ssh_backup` SSH key already
  used to push to `rpi4`. Revert to `rpi4` once it is back; do not leave this
  as the permanent target without updating
  [`restore-postgres.md`](restore-postgres.md) and
  [`restore-gitlab.md`](restore-gitlab.md), which both hard-code `rpi4`.

**Executed 2026-09-07** (`rpi4` still down): rerouted, not fixed —
`hosts/proxmox-dev/interim-backup-relay.nix` adds a `backup-relay` user
authorized with the same public key rpi4 already trusts, and
`services/postgres.nix` / `services/gitlab.nix` each got a `backupTarget`
let-binding pointing rsync at
`backup-relay@proxmox-dev:/var/backup-relay/{postgres,gitlab}_backups/`
instead of `rpi4`. `restore-postgres.md` and `restore-gitlab.md` both note
the temporary target. **To revert:** delete
`hosts/proxmox-dev/interim-backup-relay.nix` and its line in `flake.nix`'s
`proxmox-dev` module list, delete the two `backupTarget` let-bindings and
restore the literal `alex@rpi4:/mnt/usb-backup/{postgres,gitlab}_backups/`
paths, then undo the temporary notes in both restore runbooks.

### Step 3 — Manually ship today's stuck dumps now

Do this regardless of which option you picked in Step 2 — it is cheap and
closes the immediate exposure window.

TrueNAS has no running `sshd` (confirmed: connections to port 22 are
refused), so a direct `scp` to `truenas-scale` will not work. Copy through
your operator workstation instead — it is off-box, which is the point:

```bash
# Postgres dump, currently the only copy, on xcloud-postgres:
ssh root@xcloud-postgres 'ls -la /var/backup/postgresql/'
scp root@xcloud-postgres:/var/backup/postgresql/all_2026-09-07_02-00-43.sql.zstd \
  ~/fleet-backups-interim/

# GitLab backup tarball, currently the only copy, on proxmox-applications-2:
ssh root@proxmox-applications-2 'ls -la /var/gitlab/state/backup/'
scp root@proxmox-applications-2:/var/gitlab/state/backup/1788743019_2026_09_07_19.0.4_gitlab_backup.tar \
  ~/fleet-backups-interim/
```

Once `rpi4` is confirmed reachable again (Step 2) and its own sync has
caught up, these two files have done their job and can be deleted from your
workstation. Until then, this is the only copy that exists off the VM that
produced it.

**Do not delete the local copies** on `xcloud-postgres` or `apps-2` after
copying — leave both the original and the interim copy until `rpi4` is
confirmed reachable and its own sync has caught up.

### Step 4 — Watch the disk that has failed this way before

```bash
ssh root@proxmox-applications-2 'df -h /'
```

If this crosses ~85% before `rpi4` recovers, manually delete the *oldest*
tarballs under `/var/gitlab/state/backup/` once you have confirmed (Step 3)
that a copy exists elsewhere. Do not let this run to 100% unattended a second
time.

### Step 5 — Confirm the things that are not on TrueNAS or Postgres

- `sops` age keys and `secrets/*/secrets.yaml` — already in git, already
  wherever your operator checkout is cloned. Confirm you have at least one
  clone off this laptop (this is the actual disaster-recovery copy of every
  secret in the fleet).
- Garage: already healthy and out of scope for this runbook
  (`cluster_healthy 1`, RF=2 across `db-1`/`db-2`). No action needed yet;
  Phase 3 of the plan covers it separately, later, with its own snapshot step.

### Go / no-go

Do not proceed past this point until all of these are true:

- [ ] Step 1 snapshot exists and is listed by `zfs list -t snapshot`.
- [ ] `rpi4` is reachable again, **or** the interim reroute in Step 2 is live.
- [ ] Today's Postgres dump and GitLab tarball exist in at least two places.
- [ ] `proxmox-applications-2` root disk is not climbing unattended.

## Phase 0 — stabilise, change nothing structural

Each step is independently revertible. Do them in any order; none of them
touch VM disks or data.

### Step 6 — Order the Phase 1 hardware

This gates everything after it, so start it now even though it is not a
config change. See the plan's
[open decision #1](../fleet-simplification-plan.md#open-decisions-for-the-operator):
one M.2 NVMe (cheapest), a mirrored pair, or reclaiming the two WD Blue
SA510s. Do not start Step 9 onward before it physically arrives and is
installed.

### Step 7 — Reschedule the TrueNAS scrub window and repin its vCPUs

Via the TrueNAS UI (Storage → Pools → scrub schedule) or `midclt`, move the
`hdd` scrub off a window that overlaps a fleet boot. Then, on the
hypervisor:

```bash
ssh root@proxmox 'qm set 100 --affinity 0-5'
```

This moves the NAS VM from the four E-cores (4.5 GHz, `cpu_capacity` 803) to
the six P-cores (5.0 GHz, `cpu_capacity` 1024). Confirm:

```bash
ssh root@proxmox 'qm config 100 | grep affinity'
```

**Rollback:** `qm set 100 --affinity 6-9`. No reboot needed; affinity applies
live.

### Step 8 — Fix `garage-bootstrap.service` and leave `proxmox-lb` at 2 GiB

`Restart=on-failure` / `RestartSec=15s` is already in `services/garage.nix`.
Do **not** deploy `proxmox-db-1`; that host is leaving inventory. The oneshot
lands on `proxmox-observability` at
[observability-monolith.md](observability-monolith.md) cutover.

Confirm `proxmox-lb` (VM 105) is still at 2 GiB, not reverted to 1 GiB:

```bash
ssh root@proxmox 'qm config 105 | grep memory'
```

Add the NVMe wear and temperature alerts (see the plan's Phase 0 item 5),
vetted against live series first
([`alert-timeseries.mdc`](../../.cursor/rules/alert-timeseries.mdc)), then a
`fleet-hardware` dashboard panel
([`grafana-dashboards.mdc`](../../.cursor/rules/grafana-dashboards.mdc)).

Correct the three documentation drifts (README topology table, `memory.md`
host RAM budget, the MTU 9000 claim in `services/proxmox-host.md`) in the
same change.

**Done when:** `systemctl --failed` is empty on every guest, the NVMe alerts
are live, docs match `qm config` and `ip link`.

## Phase 1 — break the circular storage dependency (staged, gated on hardware)

Do not start this section until Step 6's drive is installed and shows up in
`lsblk` on the hypervisor. Create the new storage first:

```bash
ssh root@proxmox 'pvesm status'   # confirm the new datastore, however you provisioned it
```

Move guests **one at a time**, smallest and least-missed first, so a mistake
on VM 105 does not cost you `proxmox-dev`'s 90 GiB mid-afternoon. Suggested
order: `proxmox-lb` (105) → `proxmox-observability` (103) →
`proxmox-applications-1`/`-2` (101/102) → `proxmox-dev` (106) →
`truenas-scale`'s own boot disk (100) last, since every other move depends
on its NFS export staying up. Skip VMs 104/107/108 if
[observability-monolith.md](observability-monolith.md) already destroyed
them.

### Steps 9–12 — the per-VM move procedure

Repeat for each VM in the order above. Example uses `proxmox-lb` (VM 105,
disk `scsi0`, target datastore `local-nvme`).

**Step 9 — snapshot, then stop the VM.**

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 30 -- \
  /usr/sbin/zfs snapshot ssd/proxmox/storage-pool@pre-move-proxmox-lb'
ssh root@proxmox 'qm shutdown 105 --timeout 60'
ssh root@proxmox 'qm status 105'   # confirm "stopped" before continuing
```

Stopping first means the disk copy in Step 10 is a clean, consistent copy —
not a live qcow2 under an active QEMU process — and it means there is nothing
running to corrupt if the copy is interrupted.

**Step 10 — copy (not move) the disk.**

```bash
ssh root@proxmox 'qm disk move 105 scsi0 local-nvme'
```

No `--delete`. This copies the qcow2 to the new datastore and rewrites
`scsi0` in the VM config to point at the copy; the original stays attached as
`unused0`. Confirm both exist:

```bash
ssh root@proxmox 'qm config 105 | grep -E "scsi0|unused0"'
```

**Step 11 — boot and verify before doing anything else.**

```bash
ssh root@proxmox 'qm start 105'
```

Wait for the guest agent, then check the things that actually matter — not
just "it booted":

```bash
ssh -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/Users/alex/code/nixos-fleet/ssh/fleet_known_hosts \
    root@proxmox-lb 'hostname; uptime; systemctl --failed --no-legend; \
    readlink /run/current-system'
```

Compare the `readlink` output against what it was before the move — the
generation must be identical; a disk copy must not change what the host
boots into. For `proxmox-lb` specifically, also confirm Caddy is actually
serving (`curl` a backend through it, as done during the original
inspection). For hosts with NFS mounts (`db-1`, `db-2`, `apps-1`, `apps-2`,
`dev`), confirm `findmnt -t nfs4` shows every mount, not a subset — a host
that boots but silently lost a mount will look healthy in `systemctl
--failed` and then fail the first write.

**If Step 11 fails:** the original disk is still attached as `unused0` on
the stopped-then-restarted VM. Stop the VM, in the Proxmox UI (or `qm
set 105 --scsi0 <original-volume-path>`) point `scsi0` back at the original
volume, remove the failed copy, start. You have not lost anything — this is
why Step 10 never uses `--delete`.

**Step 12 — clean up only after verification holds for a full day.**

Do not run this immediately after Step 11. Let the VM run normally for at
least 24 hours — long enough to see a real workload cycle, a Prometheus
scrape gap if there is one, a log rotation — before removing the safety net.

```bash
ssh root@proxmox 'qm set 105 --delete unused0'
```

Then, once **every** VM in the order above has been moved and verified for a
day:

```bash
ssh root@proxmox 'qm guest exec 100 --timeout 30 -- \
  /usr/sbin/zfs destroy ssd/proxmox/storage-pool@pre-move-proxmox-lb'
```

Keep the blanket `pre-migration-2026-09-07` snapshot from Step 1 until the
whole Phase 1 migration (all nine VMs, if `truenas-scale`'s own disk moves
too) is complete and stable, then destroy it the same way.

## Close-out

- [ ] Every guest's `scsi0` (or equivalent) points at the new local datastore.
- [ ] `qm config 100` shows the NAS VM's own boot disk off `local-lvm` too
      (Phase 1, plan step 3), so the aging 21%-worn NVMe is no longer the sole
      copy of anything but rebuildable VM state.
- [ ] No `unusedN` disks remain attached anywhere (Step 12 completed for all).
- [ ] The `pre-migration-2026-09-07` snapshot and all per-VM
      `pre-move-<hostname>` snapshots are destroyed.
- [ ] `rpi4` is confirmed reachable and both backup timers have a **passed**
      run since it came back, not just a scheduled one.
- [ ] `make check-inventory` and `make lint` pass.
- [ ] The fleet-simplification-plan.md open decisions are updated with what
      was actually chosen in Step 6.

At this point Phase 0 and Phase 1 of
[`fleet-simplification-plan.md`](../fleet-simplification-plan.md) are done.
Phase 2 plus Garage-on-obs-1 is
[observability-monolith.md](observability-monolith.md) — it deletes VMs 104,
107, and 108 after a new RF=1 cluster is serving `proxmox-lb:3902`.

## What this runbook does not cover

- Restoring Postgres or GitLab from the dumps this runbook ships to a second
  location — see [restore-postgres.md](restore-postgres.md) and
  [restore-gitlab.md](restore-gitlab.md). Neither has been drill-tested;
  this runbook does not change that, it only ensures a second copy exists to
  eventually test against.
- Rolling a NixOS generation back after a bad `switch-to-configuration` — see
  [rollback.md](rollback.md). Not relevant here since Phase 0/1 do not deploy
  new generations to most hosts (Step 8's `garage-bootstrap` fix is the one
  exception).
- Phases 2 through 5 of the original plan. Phase 2 and Garage-on-obs-1:
  [observability-monolith.md](observability-monolith.md). Retiring the
  internal LB and de-clustering Keycloak/Vikunja still need their own
  runbooks before execution.
