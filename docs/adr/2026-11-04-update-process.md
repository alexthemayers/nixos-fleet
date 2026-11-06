---
status: accepted
date: 2026-11-04
---

# Update cadence for the hypervisor and the Debian guests

## Context and Problem Statement

The NixOS guests rolled forward with `flake.lock` and every generation was a
rollback. The Debian guests (VM 109 to 112) and the Proxmox hypervisor are
ordinary apt systems: nothing set an update policy, nothing reported what was
pending, and the only hypervisor update path was a manual
`--tags apt_upgrade`. How are they kept patched without surprise outages?

## Decision Drivers

* Every guest root and the GitLab state live on TrueNAS NFS, so TrueNAS or
  hypervisor work is a full outage of 10 to 12 minutes
* There is no out-of-band console on the hypervisor and no NixOS rollback
  disk on the guests
* The hypervisor carries out-of-tree DKMS modules (`r8125`,
  `i915-sriov-dkms`) that can fail to build on a new kernel
* `gitlab-ce` is held and upgrades along GitLab's required path only
* Container images are digest-pinned, so they never move on their own

## Considered Options

* Everything automatic, including reboots and the hypervisor
* Everything manual, on request
* Automatic security patches and reboots on guests; scheduled manual windows
  for everything that can take the fleet down

## Decision Outcome

Chosen option: "Automatic security patches and reboots on guests; scheduled
manual windows for everything that can take the fleet down", because a guest
reboot costs minutes of one service while the hypervisor and TrueNAS cost the
whole fleet.

* **Guests, nightly, automatic.** `unattended-upgrades` applies Debian and
  Debian-Security updates at 03:30 (`fleet.debian_guest` `base` role). When
  an update asks for a reboot, the guest restarts in its own slot: VM 109 at
  04:00, 110 at 04:20, 112 at 04:40, 111 at 05:00. They are after the 02:00
  Postgres and 03:00 GitLab backups.
* **Guests, monthly, manual.** Third-party repositories (Tailscale, Vector,
  GitLab Runner), container image digests, and `gitlab-ce` change only in the
  window described in [updates.md](../runbooks/updates.md). So does the
  Nix flake input bump for the NixOS hosts.
* **Hypervisor and TrueNAS, quarterly, manual,** plus out of band within 72
  hours for a critical CVE in the kernel, QEMU, openssh, or Tailscale. The
  order, snapshots, DKMS check, and verification are in
  [updates.md](../runbooks/updates.md).
* Pending security updates, a stuck reboot, a missed window, and a stale apt
  cache alert from `apt_upgrades_pending` and `node_reboot_required`
  (`updates` group in `collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml`, dashboard `fleet-updates`).

### Consequences

* Good, because security patches reach the guests without an operator and
  every missed step is an alert
* Good, because the 10 to 12 minute outage happens four times a year, on a
  schedule
* Bad, because a bad nightly update can restart a guest unattended. The
  qcow2 snapshot is taken only in the manual windows
* Bad, because the quarterly hypervisor cadence leaves PVE point releases
  unapplied for up to three months

## Validation

`HostSecurityUpdatesPending`, `HostRebootRequired`, `HostUpdatesStale`,
`HypervisorUpdatesStale`, and `HostAptCacheStale` have live series for all
five Debian hosts. The `base` role is applied on each guest and
`unattended-upgrade --dry-run` runs clean.
