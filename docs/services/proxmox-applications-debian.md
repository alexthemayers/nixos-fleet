# Debian applications guest

**Host:** `proxmox-applications-debian` (VM 109) · **Collection:**
[`fleet.debian_guest`](../../collections/ansible_collections/fleet/debian_guest)

Debian 13 replacement platform for `proxmox-applications-1` (VM 101).
The collection installs the VM on `proxmox` and maintains the guest.
It is not part of [`ansible/proxmox.yml`](../../ansible/proxmox.yml).
See
[2026-11-01-debian-applications-guest.md](../adr/2026-11-01-debian-applications-guest.md),
[2026-11-03-debian-guest-merged-playbook.md](../adr/2026-11-03-debian-guest-merged-playbook.md),
[2026-11-03-debian-guest-rootless-podman.md](../adr/2026-11-03-debian-guest-rootless-podman.md).

Application services run here as rootless Podman system units
(`User=<app>` + `podman run`, digest-pinned). VM 101 was destroyed on
2026-11-04. This guest uses the same Postgres and NFS datasets. The iGPU is
`hostpci1`. Native packages and trees were removed after soak
(`roles/apps/tasks/cleanup.yml`); Paperless still bind-mounts
`/opt/paperless`.

## Hardware

Same Proxmox shape as VM 101. Cloud-init (`ide2`) is the Debian
installer and is the extra device.

| Property | Value |
|----------|-------|
| VMID | 109 |
| CPU | `host`, 6 cores |
| RAM | 12 GiB, balloon off |
| Root | `truenas-storage:109/vm-109-disk-0.qcow2`, 35 GiB, virtio-scsi, `iothread`, `discard`, `cache=none` |
| NIC | one VF from PCI map `Network-SRIOV`; MAC `82:cc:a5:22:e5:09` |
| virtio `net0` | `vmbr0`, `link_down=1`. Traffic stays on the X710 VF |
| BIOS | SeaBIOS (same as VM 101; no OVMF line in `qm config`) |
| Boot | `onboot: 1`, `startup: order=2`, same as the other guests |
| iGPU | `hostpci1: 0000:00:02.0` (attached; VM 101 was destroyed) |
| Kernel | `linux-image-amd64`. The cloud kernel has no `iavf` module |

Image pin: Debian 13 genericcloud `20261026-2643`.

## Install and maintain

```bash
make deploy-debian-guest
make debian-guest-check
```

Inventory host `proxmox` uses SSH config. When that name does not
resolve:

```bash
PROXMOX_ANSIBLE_HOST=<reachable-address> make deploy-debian-guest
```

The address is an environment override, not a value in git. Needs
Ansible ≥ 2.15 and the collections in `requirements.yml` next to the
playbook (`ansible.posix`, `community.general`, both version-pinned). Vendor
APT keys are sha256-pinned
([ADR](../adr/2026-11-06-pin-ansible-downloads.md),
[refresh](../runbooks/updates.md)). No vault password.

A full run creates the VM if it is missing, boots it, configures
Debian, then sets virtio `link_down`. Later runs are the same playbook.
`--tags install` skips guest packages. `--tags maintain` does not
create the VM. Do not `--tags install` on a half-built guest and expect
the VF to be the only NIC; `link_down` is tagged `network` and runs
after the guest has an address.

## Updates

Debian and Debian-Security updates apply at 03:30 and the guest restarts at
04:00 when an update asks for it (`unattended-upgrades`, `base` role).
Third-party repositories and images change in the monthly window:
[updates.md](../runbooks/updates.md).

## What it configures

Hostname, locale `en_US.UTF-8`, timezone `Africa/Johannesburg`, SSH
keys (operator key and `root@proxmox`), qemu guest agent (cicustom
vendor snippet on create), chrony, NFS client, Tailscale, node and
systemd exporters on the tailnet, Vector, default-drop nftables, and
the xe guest kernel line from
`hosts/proxmox-applications-1/configuration.nix` (`module_blacklist=i915`,
`xe.force_probe=7d67`). `alex` is not managed (no sudo grant). No
reboot from the playbook. GPU cmdline applies on the next boot, which
matters only after the iGPU moves.

Join Tailscale by hand:

```bash
tailscale up --hostname=proxmox-applications-debian
```

Use an auth key from the operator, not a value committed here.
Apply-time secrets come from
`secrets/proxmox-applications-debian/secrets.yaml` (alex-only;
[adr/2026-11-06-ansible-guest-secrets.md](../adr/2026-11-06-ansible-guest-secrets.md)).

## Observability

Node exporter and systemd exporter bind the tailnet IP. Vector ships
journals. Scrape jobs list `proxmox-applications-debian` in
[prometheus.md](prometheus.md).

## iGPU

`debian_guest_igpu` defaults true. VM 101 was destroyed; the cutover
`igpu.yml` path is gone. The guest already has `hostpci1:
0000:00:02.0`. Cmdline stays `module_blacklist=i915
xe.force_probe=7d67`.

## Boot

NFS mounts are ordered after `tailscaled.service` and
`wait-truenas.service` with a repeated `x-systemd.after=` and
`x-systemd.requires=` for each unit. `mount.nfs` resolves
`truenas-scale` through MagicDNS, which is not answering when
`tailscaled` first becomes active. A space in one option value is an
fstab field break, and `\040` is kept as a single unit name.

`kernel.printk` is `3 4 1 3`. OpenArena's `ioq3ded` AppArmor profile
audits every file under `/var/games/openarena-server`, and the default
`7 4 1 7` paints those lines over the tty1 login prompt.
`openipmi.service` is masked; the guest has no BMC, and a failed LSB
unit leaves the boot degraded.

Application NFS mounts do not set `x-systemd.idle-timeout`. Services
bind these paths in their own mount namespace, so the host automount
sees no activity. A 10 minute idle unmount then stops any unit that
`Requires` the mount, and that stop is a clean exit, so
`Restart=on-failure` leaves the service down.
