# Proxmox VE hypervisor

**Host:** `proxmox` (`192.168.3.100`) · **Playbook:** [ansible/proxmox.yml](../../ansible/proxmox.yml)

The hypervisor is Debian/Proxmox VE, not NixOS. Configuration lives under
[`ansible/`](../../ansible/). See
[2026-08-31-proxmox-ansible.md](../adr/2026-08-31-proxmox-ansible.md).
Guest RAM sums: [memory.md](../memory.md). Crash triage:
[proxmox-hardware-crash.md](../runbooks/proxmox-hardware-crash.md).

## Hardware

Inspected 2026-09-07. Confirm live values on the host before sizing a
guest; `ProxmoxMemoryPressureHigh` and `ProxmoxCPUThrottlingActive` are
the current signals.

| Property | Value |
|----------|-------|
| Board / BIOS | Gigabyte `B860I AORUS PRO ICE` (Mini-ITX), AMI `F6`, 2025-03-11 |
| CPU | Intel Core Ultra 5 225 — 6 P-cores (`cpu0-5`) + 4 E-cores (`cpu6-9`), no SMT |
| RAM | 94 GiB physical. Guest commit is the sum in [memory.md](../memory.md). |
| PVE | Debian/Proxmox VE; kernel from the hypervisor playbook |
| Boot / VM disk | one 238 GiB DRAM-less NVMe (`local-lvm` for VM 100 only) |
| Pass-through disks | 2x Seagate 23.6 TB, 2x WD Blue SA510 1 TB — all to VM 100 |
| Thermal | Package trip 85 °C. `package_throttle_count` and ACPI BERT are scraped. |

Guests (VM ids from PVE):

| VM | Guest | Role |
|----|-------|------|
| 100 | `truenas-scale` | NAS, NFS, ZFS. Root on `local-lvm`. |
| 109 | `proxmox-applications-debian` | Apps, iGPU. Debian. NFS qcow2. |
| 110 | `proxmox-gitlab-debian` | GitLab and the registry caches. Debian. |
| 111 | `proxmox-observability-debian` | Prometheus, Loki, Grafana, ntfy. Debian. |
| 112 | `proxmox-dev-debian` | Builder and GitLab runner. Answers as `proxmox-dev`. |

109–112 are `fleet.debian_guest`, not this playbook, with `onboot` and
`startup: order=2`.
[proxmox-applications-debian.md](proxmox-applications-debian.md),
[proxmox-gitlab-debian.md](proxmox-gitlab-debian.md),
[proxmox-observability-debian.md](proxmox-observability-debian.md),
[proxmox-dev-debian.md](proxmox-dev-debian.md).

Destroyed 2026-11-04: VMs 101 (`proxmox-applications-1`), 102
(`proxmox-applications-2`), 103 (`proxmox-observability`), and 106
(`proxmox-dev`), including their qcow2 disks. The per-host `secrets/`
directories stay. The TrueNAS zvol `ssd/garage-iscsi` stays.
Destroyed 2026-09-07: VMs 104 (`proxmox-observability-2`), 105
(`proxmox-lb`), 107 (`proxmox-db-1`), 108 (`proxmox-db-2`). Guest roots
stay on TrueNAS NFS
([nfs-vm-roots](../adr/2026-09-07-nfs-vm-roots.md)).

## Deploy

```bash
make proxmox-host-check     # dry run
make deploy-proxmox-host    # apply
```

Needs Ansible collections (`ansible-galaxy collection install -r ansible/requirements.yml`;
version-pinned) and `ansible/.vault_pass.txt` (gitignored). The Datadog and
Tailscale APT keys are sha256-pinned
([ADR](../adr/2026-11-06-pin-ansible-downloads.md)). Networking changes are written but
not applied; run `ifreload -a` on the host after reviewing the diff. Kernel
and modprobe changes need a reboot.

## Updates

Quarterly, by hand, in the window in
[updates.md](../runbooks/updates.md) ([ADR](../adr/2026-11-04-update-process.md)).
There is no unattended-upgrades here. Two traps:

- `--tags packages` (or any tag that includes the `packages` role) also runs
  the `apt_upgrade` task, whose `never` tag does not stop it when its role tag
  is selected. It runs a full `dist-upgrade`. Use `--tags monitoring` or a
  narrower role tag unless you mean to upgrade.
- DKMS builds run in the kernel postinst. `r8125` is needed. `i915-sriov-dkms`
  is installed but not used at runtime (the iGPU is bound whole to `vfio-pci`
  for VM 109), and it does not build on `proxmox-kernel-7.0.14-28`
  (`drm_exec_for_each_locked_object` takes two arguments there). A failed
  build leaves the kernel package half configured. Check `dkms status` and
  `dpkg --audit` before any reboot.

The apt, nvme, and smartmon textfile collectors write
`/var/lib/prometheus/node-exporter`, the package default, which the exporter
reads (it used to read `/var/lib/prometheus-node-exporter` and never saw
them). `node_reboot_required` never goes to 1 here: PVE kernels do not write
`/var/run/reboot-required`, so compare `uname -r` with the newest installed
`proxmox-kernel-*` before a reboot window.

## What it manages

Hostname, APT repos, packages, pmxcfs (`datacenter.cfg`, storage, PCI maps,
users), GRUB/IOMMU/VFIO, `vmbr0` + X710 SR-IOV, iGPU vfio binding, D-Bus
limits, node/systemd/smartctl exporters, Vector → `proxmox-observability:3100`, Tailscale
on port `41639`, and the PVE subscription nag hook. Hardware telemetry
(`hardware-telemetry.service` / `.timer`) writes VFIO binding status, SR-IOV
per-VF drop counters, trust mode, and rasdaemon MCE/AER counts to the
node-exporter textfile collector `/var/lib/prometheus/node-exporter/hardware.prom`.
`node_hardware_pci_driver_bound{device_name="igpu"}` is a label-stable `0`/`1`
gauge (the bound driver string lives on `node_hardware_pci_driver_info`), and
DMAR/AER kernel-log counters are read from `journalctl -k -b` so they stay
monotonic within a boot. The same script exports `node_hardware_bert_error_records`
(ACPI BERT fatal error records captured for the previous boot — a hardware-crash
signal), `node_hardware_bert_enabled` (0 if the kernel cmdline contains
`bert_disable`, a boolean even as `=0`), and `node_cpu_microcode_info`; BIOS
version comes from node-exporter's `node_dmi_info`. SMART alerts, hardware
hypervisor alerts
(`ProxmoxCPUTemperatureHigh`, `ProxmoxCPUThrottlingActive`, `ProxmoxHostSwapping`,
`ProxmoxMemoryPressureHigh`/`Critical`, `VFIODriverUnbound`,
`SRIOVVirtualFunctionsMissing`, `HardwareMCEError`, `HardwareMemoryControllerErrors`,
`PCIeAERErrorsHigh`, `ProxmoxHardwareErrorBERT`, `ProxmoxBERTDisabled`,
`ProxmoxBoardSensorHot`, `ProxmoxBIOSOutdated`, `NodeInterruptStorm`,
`SmartctlNvmeWearHigh` / `Critical` on `smartctl_device_percentage_used`),
and SR-IOV alerts are in
[`roles/observability/files/rules.yaml`](../../collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml). Dashboard:
`fleet-hardware`. Hard-reset triage:
[`docs/runbooks/proxmox-hardware-crash.md`](../runbooks/proxmox-hardware-crash.md)
(incidents: 2026-09-04, 2026-09-07 SoC CrashLog after a 94 °C package soak).

`NodeInterruptStorm` is hardware IRQs on `proxmox` above 120k/s (7d max
87k). It does **not** page on `node_context_switches_total`: 100k CS/s is
normal KVM (LOC + posted-interrupt wakeup) on this host. SR-IOV drops stay
on `SRIOVNetworkPacketDropsHigh`.

Vector pushes journald to Loki at `proxmox-observability:3100`. Debian trixie
is systemd 257, so the hypervisor uses `current_boot_only: true` (Vector 0.57
rejects `false` on systemd 250–257). NixOS hosts stay on `false`.

## Users and OpenID

Realm `Keycloak` (`username-claim preferred_username`, `autocreate`,
default login). Keycloak user `alex.mayers` is Proxmox userid
`alex.mayers@Keycloak`. Ansible
[`user.cfg.j2`](../../ansible/roles/pve_config/templates/user.cfg.j2)
grants Administrator on `/` to that user and `root@pam`.

Do not grant this in the UI only: `pve_config` replaces
`/etc/pve/user.cfg`. Do not use `alex@keycloak` (wrong username and
realm case). See
[2026-09-07-proxmox-openid-admin.md](../adr/2026-09-07-proxmox-openid-admin.md).

Apply with `--tags pve_config` when only cluster files changed:

```bash
cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags pve_config
```

## Secrets

`ansible/group_vars/all/vault.yml` holds the Keycloak OpenID client key for
`/etc/pve/domains.cfg`. That file is Ansible vault, not sops. The password
file is local-only.
