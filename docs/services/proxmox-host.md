# Proxmox VE hypervisor

**Host:** `proxmox` (`192.168.3.100`) · **Playbook:** [ansible/proxmox.yml](../../ansible/proxmox.yml)

The hypervisor is Debian/Proxmox VE, not NixOS. Configuration lives under
[`ansible/`](../../ansible/). See
[2026-08-31-proxmox-ansible.md](../adr/2026-08-31-proxmox-ansible.md).

## Deploy

```bash
make proxmox-host-check     # dry run
make deploy-proxmox-host    # apply
```

Needs Ansible collections (`ansible-galaxy collection install -r ansible/requirements.yml`)
and `ansible/.vault_pass.txt` (gitignored). Networking changes are written but
not applied; run `ifreload -a` on the host after reviewing the diff. Kernel
and modprobe changes need a reboot.

## What it manages

Hostname, APT repos, packages, pmxcfs (`datacenter.cfg`, storage, PCI maps,
users), GRUB/IOMMU/VFIO, `vmbr0` + X710 SR-IOV, iGPU vfio binding, D-Bus
limits, node/systemd/smartctl exporters, Alloy → `proxmox-lb:3100`, Tailscale
on port `41639`, and the PVE subscription nag hook. Hardware telemetry
(`hardware-telemetry.service` / `.timer`) writes VFIO binding status, SR-IOV
per-VF drop counters, trust mode, and rasdaemon MCE/AER counts to the
node-exporter textfile collector `/var/lib/prometheus-node-exporter/hardware.prom`.
`node_hardware_pci_driver_bound{device_name="igpu"}` is a label-stable `0`/`1`
gauge (the bound driver string lives on `node_hardware_pci_driver_info`), and
DMAR/AER kernel-log counters are read from `journalctl -k -b` so they stay
monotonic within a boot. SMART alerts, hardware hypervisor alerts
(`ProxmoxCPUTemperatureHigh`, `ProxmoxCPUThrottlingActive`, `ProxmoxHostSwapping`,
`VFIODriverUnbound`, `SRIOVVirtualFunctionsMissing`, `HardwareMCEError`,
`PCIeAERErrorsHigh`), and SR-IOV alerts are in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). Dashboard:
`fleet-hardware`.

Alloy does not push to a single observability VM. Loki clients use the
internal Caddy listener on `proxmox-lb:3100`.

## Secrets

`ansible/group_vars/all/vault.yml` holds the Keycloak OpenID client key for
`/etc/pve/domains.cfg`. That file is Ansible vault, not sops. The password
file is local-only.
