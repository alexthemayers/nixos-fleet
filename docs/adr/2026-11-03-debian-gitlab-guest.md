---
status: accepted
date: 2026-11-03
---

# GitLab moves to a Debian guest in fleet.debian_guest

## Context and Problem Statement

`proxmox-applications-2` (VM 102) is the NixOS GitLab host: Omnibus is
not what it runs today, the database is on `xcloud-postgres`, and the
repositories sit on an NFS loop image. VM 109 already showed how a
Debian guest is installed from `fleet.debian_guest`. How should GitLab
move onto Debian without a second writer on that database or those
images?

## Decision Drivers

* GitLab is CI of record. Two processes must not use the `gitlab`
  database or `gitlab-state.img` at once.
* VM 102 stays bootable for rollback until the Debian guest has been
  checked and has taken its own backup.
* The public names `gitlab.alexmayers.co.za` and
  `registry.alexmayers.co.za` stay. Caddy is retargeted in a later
  deploy, not in the same step as creating the guest.
* Guest roots stay on TrueNAS NFS.

## Considered Options

* Rebuild Debian in place on VM 102
* A new collection, or roles added to `ansible/proxmox.yml`
* A second playbook in `fleet.debian_guest` that installs pinned
  Omnibus `gitlab-ce` and bind-mounts the existing loop images

## Decision Outcome

Chosen option: "A second playbook in `fleet.debian_guest` that installs
pinned Omnibus `gitlab-ce` and bind-mounts the existing loop images",
because the guest lifecycle is already that collection's, and a new VM
can be stopped without destroying VM 102.

VM 110 is `proxmox-gitlab-debian`: Debian 13, 6 cores, 12 GiB, 35 GiB
qcow2 on `truenas-storage`, one X710 VF, no iGPU. Apply with
`make deploy-debian-gitlab` only after `qm stop 102`. Omnibus is held
at the version VM 102 was running (19.0.4). Postgres stays on
`xcloud-postgres` through PgBouncer. The role refuses to mount
`gitlab-state.img` or `container-registry.img` while VM 102 is running.
It does not restore a backup into Postgres and it does not chown the
images. User `gitlab` keeps uid/gid 165.

MagicDNS is `proxmox-gitlab-debian`. The restored Tailscale node was
renamed to that, and `xcloud-caddy` already dials it. VM 103
(`proxmox-observability`) is stopped; its last generation still lists
`proxmox-applications-2` for smokeping, which no longer resolves.
Boot that host from this tree, or the prober exits.

### Consequences

* Good, because rollback is `qm stop 110`, `qm start 102`, and a
  Tailscale rename back to `proxmox-applications-2`. Caddy dials
  `proxmox-gitlab-debian`.
* Good, because an unattended upgrade cannot migrate the shared
  database out from under VM 102.
* Bad, because `gitlab.alexmayers.co.za` is down while nginx on VM 110
  is not listening on `:8080`.
* Bad, because Omnibus and the NixOS module do not share a config
  language. `gitlab.rb` has to keep the cache bypass, the pool size,
  and the encryption keys.

## Validation

`qm status 102` is `stopped` before `make deploy-debian-gitlab`.
`qm config 110` shows `proxmox-gitlab-debian`, `memory: 12288`, and
`scsi0` on `truenas-storage`. `apt-mark showhold` includes `gitlab-ce`.
`/-/users/sign_in` answers on `proxmox-gitlab-debian:8080`. A newer
package version is a failed check: it means the database may have
migrated.

## Pros and Cons of the Options

### Rebuild Debian in place on VM 102

* Good, because there is no second 12 GiB guest.
* Bad, because a failed install leaves no disk to start.

### A new collection, or roles added to ansible/proxmox.yml

* Good, because the GitLab play would be obvious to find.
* Bad, because VM create, cloud-init, and the VF setup would be copied
  or mixed into the hypervisor run.

### A second playbook in fleet.debian_guest that installs pinned Omnibus gitlab-ce and bind-mounts the existing loop images

* Good, because install and package config share the collection that
  already creates Debian guests.
* Bad, because the playbook has to override guest vars that default to
  VM 109, and a mistake mounts the loop images twice.

## More Information

[proxmox-gitlab-debian.md](../services/proxmox-gitlab-debian.md),
[2026-11-01-debian-applications-guest.md](2026-11-01-debian-applications-guest.md),
[gitlab.md](../services/gitlab.md).
