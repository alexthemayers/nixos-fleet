---
status: accepted
date: 2026-11-01
---

# Debian applications guest is its own Ansible collection

## Context and Problem Statement

`proxmox-applications-1` (VM 101) is a NixOS guest: 6 cores, 12 GiB, a
35 GiB root on `truenas-storage`, one X710 VF, and the only consumer of
iGPU `0000:00:02.0`. The hypervisor is already Ansible
([2026-08-31-proxmox-ansible](2026-08-31-proxmox-ansible.md)). How should
a Debian replacement of that guest be installed and maintained?

## Decision Drivers

* VM 101 keeps serving Jellyfin, Keycloak, and the rest until a later
  cutover. The iGPU cannot be attached to two VMs.
* The hypervisor playbook and the guest playbook will probably merge, but
  not in this change.
* Guest roots stay on TrueNAS NFS
  ([2026-09-07-nfs-vm-roots](2026-09-07-nfs-vm-roots.md)).
* Ansible vault stays out of sops-nix. This guest has no vault file.

## Considered Options

* Keep the applications guest on NixOS only
* Add the Debian guest's roles to `ansible/proxmox.yml`
* A separate collection that creates the VM and maintains Debian

## Decision Outcome

Chosen option: "A separate collection that creates the VM and maintains
Debian", because the guest lifecycle is not the hypervisor's, and the
two trees can be merged later without mixing them now.

Collection `fleet.debian_guest` lives at
`collections/ansible_collections/fleet/debian_guest`. Apply with
`make deploy-debian-guest`. VM 109 is `proxmox-applications-debian`:
Debian 13 genericcloud, 6 cores, 12 GiB, 35 GiB qcow2 on
`truenas-storage`, one VF from `Network-SRIOV`, virtio `net0` left
`link_down` once the VF has an address. `onboot` and `startup: order=2`
match the other guests. `debian_guest_igpu` is true: the play attaches
`0000:00:02.0` only when VM 101 is stopped, and deletes it from 101
first. Application services stay on VM 101.

### Consequences

* Good, because a Debian platform can be rebuilt without touching
  `ansible/proxmox.yml` or the NixOS apps host.
* Bad, because VM 109 does not run the applications yet. Do not run it
  at the same time as VM 101 (24 GiB combined, one iGPU).
* Bad, because `tailscale up` is still manual. No exporter is installed,
  so there is no scrape target to page on.

## Validation

`qm config 109` shows `proxmox-applications-debian`, `memory: 12288`,
`scsi0: truenas-storage:…`, `hostpci0: mapping=Network-SRIOV`,
`hostpci1: 0000:00:02.0` only while VM 101 is stopped, and `net0` with
`link_down=1` after the first successful apply. `make deploy-debian-guest`
is idempotent after that.

## Pros and Cons of the Options

### Keep the applications guest on NixOS only

* Good, because nothing new shares the 94 GiB host.
* Bad, because there is no Debian install path when the NixOS guest
  is the thing being replaced.

### Add the Debian guest's roles to `ansible/proxmox.yml`

* Good, because one playbook would own every Proxmox-side change.
* Bad, because guest packages, cloud-init, and the iGPU cutover guard
  would land in the hypervisor run before that merge is deliberate.

### A separate collection that creates the VM and maintains Debian

* Good, because install (`qm`) and later package runs share one
  playbook without editing the hypervisor roles.
* Bad, because operators learn a second `make` target, and the
  collection reaches the hypervisor over SSH to create the guest.

## More Information

[proxmox-applications-debian.md](../services/proxmox-applications-debian.md),
[proxmox-host.md](../services/proxmox-host.md),
[memory.md](../memory.md).
