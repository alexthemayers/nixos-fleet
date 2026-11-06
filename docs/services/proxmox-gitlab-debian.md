# Debian GitLab guest

**Host:** `proxmox-gitlab-debian` (VM 110) · **Collection:**
[`fleet.debian_guest`](../../collections/ansible_collections/fleet/debian_guest)

Debian 13 GitLab host that replaces `proxmox-applications-2` (VM 102).
The same collection installs the VM and maintains the guest. See
[2026-11-03-debian-gitlab-guest.md](../adr/2026-11-03-debian-gitlab-guest.md).

```bash
make deploy-debian-gitlab
make debian-gitlab-check
```

VM 102 was destroyed. A normal apply converges the guest; there is no
`nixos_vmid` guard.

`debian-gitlab-check` does not call `qm`. Public HTTPS for
`gitlab.alexmayers.co.za` and `registry.alexmayers.co.za` is served by
this guest. Caddy on `xcloud-caddy` dials `proxmox-gitlab-debian:8080`
and `:5005`.

## Hardware

| Property | Value |
|----------|-------|
| VMID | 110 |
| CPU | `host`, 6 cores |
| RAM | 12 GiB, balloon off |
| Root | `truenas-storage`, 35 GiB, virtio-scsi |
| NIC | one VF from PCI map `Network-SRIOV`; MAC `82:cc:a5:22:e5:0a` |
| virtio `net0` | `vmbr0`, `link_down=1`. Traffic stays on the X710 VF |
| Boot | `onboot: 1`, `startup: order=2` |
| iGPU | none |
| Tailscale | hostname `proxmox-gitlab-debian`, listen port `41654` |

Image pin: Debian 13 genericcloud `20261026-2643`.

## Updates

Debian and Debian-Security updates apply at 03:30 and the guest restarts at
04:20 when an update asks for it. Third-party repositories and images change
in the monthly window: [updates.md](../runbooks/updates.md).

## GitLab

Omnibus `gitlab-ce` held at `19.0.4-ce.0`. `apt-mark hold` and an
unattended-upgrades blacklist stop a newer package from migrating the
database. User `gitlab` is uid/gid 165, the ids from VM 102, so the
loop image is not chowned.

Postgres stays on `xcloud-postgres` port 5432 (PgBouncer, pool 8,
transaction mode). The Rails pool is 5, matching the NixOS
`database.yml`. There is no local Postgres. Puma is 2 workers and 1–4
threads. Sidekiq concurrency is 10. Nginx listens on `8080` without
TLS. Authenticated responses are not cached. The registry listens on
`5005`.

Secrets are decrypted from `secrets/proxmox-applications-2/secrets.yaml`
at apply time into `/etc/gitlab/gitlab-secrets.json` and root-only
files. `gitlab.rb` reads those files. It does not contain the secret
values.

## Storage

One writer. The role does not create or format an image that is missing.

| Mount | Source |
|-------|--------|
| `/mnt/nfs-gitlab` | `truenas-scale:/mnt/ssd/gitlab` (no idle unmount). The guest resolver does not know that name, so `/etc/hosts` maps it to `192.168.3.9`. |
| `/var/gitlab/state` | `/mnt/nfs-gitlab/gitlab-state.img` |
| `/mnt/nfs/container-registry` | `truenas-scale:/mnt/ssd/container-registry` |
| `/mnt/ssd/container-registry` | `container-registry.img` |
| registry blobs | `/mnt/ssd/container-registry/gitlab` bind-mounted onto the Omnibus registry directory |

Repositories, uploads, artifacts, LFS, and packages stay on
`gitlab-state.img`. Omnibus is pointed at those directories. A
`gitlab-backup restore` is not part of the move. The backup taken on
VM 102 before the stop is the fallback if a directory cannot be bound.

`gitlab-backup.timer` runs at 03:00. `gitlab-backup-sync.service`
copies, checksums, then deletes archives to
`backup-relay@proxmox-dev:/var/backup-relay/gitlab_backups/`. The unit
puts PostgreSQL 17's `pg_dump` first on `PATH`. Pull-through caches on
ports `5000`–`5003` are rootless Podman, user `docker-registry` uid
994 / gid 984 (Debian already uses 993 for `clock`), with the same
subuid range VM 102 used. Garbage collection is Sunday 04:00.

## Rollback

VM 102 and its qcow2 disk were destroyed on 2026-11-04. There is no
NixOS GitLab guest to start. `secrets/proxmox-applications-2` remains.
GitLab data is the NFS loop images this guest mounts. A verified backup
is on VM 112 under `/var/backup-relay/gitlab_backups/`.

## Observability

Node exporter and the systemd exporter listen on the tailnet address
only. Vector ships the journal to `proxmox-observability:3100`. The
Prometheus scrape, smokeping host, and Caddy upstream are in the Nix
tree as `proxmox-gitlab-debian` and are not deployed with the guest.
Deploy them only after this name resolves. Dropping
`proxmox-applications-2` from smokeping before its Tailscale node is
still registered is safe; deleting the node first makes
`smokeping_prober` exit.
