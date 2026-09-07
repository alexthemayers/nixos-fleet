# Proxmox VE Ansible Playbook

Ansible configuration management for the Proxmox VE 9.2 host at `192.168.3.100`.

---

## Overview

This playbook manages 100% of the Proxmox VE host configuration, package repositories, cluster definitions, installed applications, background exporters, and hardware tuning. It is fully idempotent — running it multiple times produces no changes once the host is in the desired state.

### Roles

| Role                | Description                                                                                          |
|---------------------|------------------------------------------------------------------------------------------------------|
| `system`            | Hostname, `/etc/hosts`, timezone, locale, sysctl cleanup, udev rules, SSH, iptables legacy, Oh-My-Zsh, fstab, aliases, postfix, chrony NTP |
| `apt_repos`         | APT repositories & keyrings (Debian trixie, Proxmox no-sub, Grafana, Tailscale, disabled enterprise) |
| `packages`          | Base admin, diagnostic, GPU tools, DKMS build deps (`build-essential`, `dkms`, `git`, `r8125-dkms`), and default services (`iperf3`, node_exp) |
| `pve_config`        | Proxmox cluster config (`datacenter.cfg`, `storage.cfg`, `mapping/pci.cfg`, `user.cfg`) via pmxcfs   |
| `kernel`            | GRUB cmdline, `/etc/modules`, `/etc/modprobe.d/` configs, `i915-sriov-dkms` assertion, old kernel purge |
| `networking`        | `/etc/network/interfaces` — bridge, SR-IOV PF, and disabled Realtek NIC                             |
| `sriov`             | Intel X710 SR-IOV: instantiates 16 VFs with trust mode (`nic-sriov`) and rebinds iavf VFs           |
| `igpu_passthrough`  | Verifies Intel Arrow Lake-S iGPU (`8086:7d67`) is bound to `vfio-pci` at runtime                    |
| `dbus`              | Raises D-Bus `max_replies_per_connection` from 128 → 512 (prevents exporter errors)                 |
| `monitoring`        | Hardware monitoring (`lm-sensors` + `rasdaemon`), cron CPU temp check, journald alerts               |
| `systemd_exporter`  | Prometheus `systemd_exporter` binary, service unit, and unit-scope filter drop-in                   |
| `smartctl_exporter` | Prometheus `smartctl_exporter` binary, systemd service unit                                         |
| `alloy`             | Grafana Alloy log forwarder (journald log shipping to Loki at `proxmox-observability:3100`) |
| `tailscale`         | Tailscale client package, custom port (`41639`), and `tailscaled` daemon service                     |
| `pve_nag`           | Removes Proxmox VE web UI subscription nag dialog and installs DPkg post-invoke hook                 |

---

## Prerequisites

- **Ansible** ≥ 2.14 plus collections:
  ```bash
  pip install ansible
  # or
  brew install ansible
  ansible-galaxy collection install -r requirements.yml
  ```
- **Vault password** at `ansible/.vault_pass.txt` (gitignored). Ask the operator
  for the password; do not commit it. `ansible.cfg` reads that file.
- **SSH alias** `proxmox` configured in `~/.ssh/config`:
  ```
  Host proxmox
      HostName 192.168.3.100
      User root
      IdentityFile ~/.ssh/id_ed25519
  ```
- Root SSH access to the Proxmox host (passwordless preferred).
- Python 3 available at `/usr/bin/python3` on the host (standard on Proxmox VE).

---

## Usage

Run from the repository root (or inside `ansible/`):

```bash
# Dry run — show what would change without making changes
make proxmox-host-check
# or: ansible-playbook -i inventory/proxmox.ini proxmox.yml --check --diff

# Full apply — configure everything
make deploy-proxmox-host
# or: ansible-playbook -i inventory/proxmox.ini proxmox.yml

# Apply a single role via tag
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags system
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags apt_repos
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags packages
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags pve_config
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags kernel
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags networking
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags sriov
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags igpu_passthrough
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags dbus
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags monitoring
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags systemd_exporter
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags smartctl_exporter
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags alloy
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags tailscale
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags pve_nag

# Apply multiple specific roles
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags system,apt_repos,packages

# Explicitly perform full APT dist-upgrade on the host
ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags apt_upgrade
```

> **After running the `kernel` role**: A reboot is required for grub/modprobe changes to take effect. The handlers run `update-grub` and `update-initramfs -u -k all` automatically — reboot manually after.

> **After running the `networking` role**: Do NOT auto-apply. Run `ifreload -a` manually on the host after reviewing the diff, as applying remotely will drop the SSH connection.

---

## Role Details and Key Files

| Role                | Key Files                                                                                              |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `system`            | `tasks/main.yml`, `handlers/main.yml`, `files/chrony.conf` (hostname, `/etc/hosts`, timezone, locale, sysctl cleanup, udev, SSH, iptables legacy, Oh-My-Zsh, fstab, aliases, postfix, chrony) |
| `apt_repos`         | `tasks/main.yml`, `handlers/main.yml` (sources inlined for Debian, PVE, Grafana, Tailscale, disabled enterprise) |
| `packages`          | `tasks/main.yml` (installs `base_packages`, DKMS build tools, `r8125-dkms`, `iperf3` & `prometheus-node-exporter`) |
| `pve_config`        | `tasks/main.yml` (`datacenter.cfg`, `storage.cfg`, `mapping/pci.cfg`, `user.cfg`)                     |
| `kernel`            | `templates/grub.j2`, `tasks/main.yml` (modprobe.d files inlined, `i915-sriov-dkms` assertion, kernel purge), `handlers/main.yml` |
| `networking`        | `templates/interfaces.j2`, `tasks/main.yml`                                                           |
| `sriov`             | `templates/nic-sriov.service.j2`, `files/iavf-vf-rebind.service`, `tasks/main.yml`                     |
| `igpu_passthrough`  | `tasks/main.yml`, `README.md`                                                                          |
| `dbus`              | `templates/system-local.conf.j2`, `tasks/main.yml`, `handlers/main.yml`                              |
| `monitoring`        | `templates/check-temps.sh.j2`, `tasks/main.yml`                                                       |
| `systemd_exporter`  | `files/systemd_exporter.service`, `files/unit-filter.conf`, `tasks/main.yml`, `handlers/main.yml`    |
| `smartctl_exporter` | `files/smartctl_exporter.service`, `tasks/main.yml`, `handlers/main.yml`                              |
| `alloy`             | `files/config.alloy`, `tasks/main.yml`, `handlers/main.yml`                                            |
| `tailscale`         | `tasks/main.yml`, `handlers/main.yml` (`/etc/default/tailscaled`)                                     |
| `pve_nag`           | `files/pve-remove-nag.sh`, `tasks/main.yml`, `handlers/main.yml`                                      |

---

## Edge Cases and System State Declarations

### 1. Kernel Soft-Lockup Watchdog & Sysctl Cleanup
- Canonical file: `/etc/sysctl.d/99-proxmox.conf`
- Managed `/etc/sysctl.conf`: Cleaned of duplicate settings and documented as redirecting to `sysctl.d/`.
- Setting: `kernel.watchdog_thresh = 30`
- Purpose: Prevents false soft-lockup kernel panics caused by transient latency spikes under heavy hypervisor I/O or VM scheduling workloads.

### 2. Firewall Legacy Alternatives (`iptables` / `ip6tables` / `ebtables`)
- Alternatives: Set to `/usr/sbin/iptables-legacy`, `/usr/sbin/ip6tables-legacy`, `/usr/sbin/ebtables-legacy`.
- Purpose: Proxmox VE firewall specifically uses legacy iptables/ebtables utilities rather than the `nft` backends to ensure rule consistency and avoid packet-dropping bugs.

### 3. Root Shell & Oh-My-Zsh Management
- Shell: Enforced as `/usr/bin/zsh`.
- Oh-My-Zsh: Checked via `/root/.oh-my-zsh` presence and automated via non-interactive installer (`RUNZSH=no KEEP_ZSHRC=yes`).

### 4. Debian Bridge Udev Rule Masking
- File: `/etc/udev/rules.d/60-bridge-network-interface.rules -> /dev/null`
- Purpose: Debian includes a default udev rule (`60-bridge-network-interface.rules`) that attempts to configure Linux bridge interfaces automatically, which conflicts with Proxmox VE bridge management (`pve-cluster` / `ifupdown2`). Masking the rule via symlink to `/dev/null` ensures PVE bridges operate without udev interference.

### 5. Intel iGPU Virtual Function Binding (Udev) & DKMS Module Assertion
- File: `/etc/udev/rules.d/99-i915-vf-vfio.rules`
- Purpose: Dynamic udev rule matching all i915 VFs (`00:02.1` to `00:02.7`, vendor `0x8086`, device `0x7d67`). Automatically overrides driver binding to `vfio-pci` upon device discovery so VFs are immediately available for VM passthrough without host kernel contention.
- Assertion: Verifies `i915-sriov-dkms` is installed on the host and fails with clear remediation instructions if absent.

### 6. Automated Old Kernel Purge
- Tasks in `roles/kernel/`: Queries installed `proxmox-kernel-*-pve-signed` packages and automatically purges all but the `kernel_cleanup_keep` (default: 2) newest kernel versions, keeping the `/boot` EFI partition clean.

### 7. Intel X710 SR-IOV Instantiation & VF Trust Mode
- Service: `/etc/systemd/system/nic-sriov.service`
- Purpose: Runs early at boot (`Before=pve-guests.service`, `BindsTo=sys-subsystem-net-devices-enp2s0f1np1.device`), resets the VF count, instantiates 16 VFs on `enp2s0f1np1`, and runs `ip link set dev enp2s0f1np1 vf $i trust on` across all 16 VFs. Setting `trust on` allows guest VMs to change MAC addresses and configure promiscuous/multicast filtering directly on the virtual function.

### 8. iavf Virtual Function Rebind
- Service: `/etc/systemd/system/iavf-vf-rebind.service`
- Purpose: On boot, there is a race condition between `i40e` PF initialization and `iavf` driver binding. The service waits 5 seconds after network targets and unbinds/rebinds all VFs under `/sys/bus/pci/drivers/iavf/` to guarantee healthy VF state before VMs start.

### 9. D-Bus Reply Limit & systemd_exporter Saturation Prevention
- File: `/etc/dbus-1/system-local.conf`
- Settings: `max_replies_per_connection = 1024`, `max_match_rules_per_connection = 1024`
- Purpose: Configured via the canonical `/etc/dbus-1/system-local.conf` path (explicitly included by `/usr/share/dbus-1/system.conf`). Prevents systemd_exporter scraping from saturating the default 128 message limit and flooding the journal with 100,000+ drop errors.

### 10. Node Exporter Thermal Zone Filter & Accurate Hardware Monitoring
- File: `/etc/default/prometheus-node-exporter`
- Setting: `ARGS="--no-collector.thermal_zone"`
- Purpose: Disables the broken ACPI thermal_zone collector that fails on Intel Arrow Lake platforms, while retaining accurate CPU package and per-core temperature metrics via the Linux `hwmon` / `coretemp` collector.

### 11. Realtek 2.5G NIC Driver State (`r8125-dkms`)
- Packages: `r8125-dkms`, `build-essential`, `dkms`, `git` are managed and kept installed.
- Driver state: Realtek `r8169` is blacklisted in `/etc/modprobe.d/blacklist-r8169.conf` and `enp131s0` is explicitly brought down in `/etc/network/interfaces` to prevent kernel panics on this board.

### 12. Time Synchronization (`chrony`)
- File: `/etc/chrony/chrony.conf`
- Service: `chrony.service` is enabled and managed.

### 13. Tailscaled Custom Port
- File: `/etc/default/tailscaled`
- Setting: `PORT="41639"`, `FLAGS=""`
- Purpose: Fixes the UDP WireGuard listen port for Tailscale to 41639, enabling predictable port-forwarding and firewall rule configuration.

### 14. Proxmox Cluster Filesystem (pmxcfs `/etc/pve/`)
- Files managed:
  - `/etc/pve/datacenter.cfg`: Global datacenter settings (`keyboard: en-us`).
  - `/etc/pve/storage.cfg`: Storage pools (`local`, `local-lvm`, and `nfs: truenas-storage` at `truenas-scale:/mnt/ssd/proxmox/storage-pool`).
  - `/etc/pve/mapping/pci.cfg`: Defines `Network-SRIOV` PCI resource mappings for all 16 SR-IOV VFs across IOMMU groups 30–45.
  - `/etc/pve/user.cfg`: Declares `alex@keycloak`, `terraform-prov@pve` user and API provider token, custom `TerraformProv` privilege role, and root/alex/terraform ACL assignments.

---

## Managed Applications & Services

| Service                      | Unit / Daemon                  | Port / Target              | Description                                                |
|------------------------------|--------------------------------|----------------------------|------------------------------------------------------------|
| **Prometheus Node Exporter** | `prometheus-node-exporter`     | `:9100`                    | CPU, memory, disk, network system metrics                  |
| **Prometheus Systemd Exp.**  | `systemd_exporter`             | `:9558`                    | Systemd unit states & service health metrics               |
| **Prometheus Smartctl Exp.** | `smartctl_exporter`            | `:9633`                    | SMART disk diagnostics & health metrics                    |
| **Grafana Alloy**            | `alloy`                        | `:12345` (HTTP / UI)       | Ships journald logs to Loki (`proxmox-observability:3100`)            |
| **iPerf3 Server**            | `iperf3`                       | `:5201`                    | Network bandwidth testing daemon                           |
| **Tailscale**                | `tailscaled`                   | `:41639` / `tailscale0`    | Mesh VPN connectivity                                      |
| **rasdaemon**                | `rasdaemon`                    | Hardware MCE DB            | Captures Machine Check Exceptions & hardware errors        |
| **Postfix**                  | `postfix`                      | `:25` (loopback-only)      | Local host system mail routing and alias delivery          |
| **Chrony NTP**               | `chrony`                       | `:123` (UDP)               | Network time synchronization                               |

---

## Directory Structure

```
ansible/
├── ansible.cfg                  # Inventory, vault password file, no retry files
├── requirements.yml             # ansible.posix + community.general
├── .vault_pass.txt              # Local vault password (gitignored; create this)
├── inventory/
│   └── proxmox.ini              # Ansible inventory (host + connection vars)
├── group_vars/
│   └── all/
│       ├── vars.yml             # Global and group variables for Proxmox VE
│       └── vault.yml            # Encrypted secrets (e.g. keycloak_client_key)
├── roles/
│   ├── common/                  # Deduplicated global handlers (reload systemd, update-grub)
│   ├── system/                  # Hostname, timezone, sysctl, udev, SSH, iptables, Oh-My-Zsh, chrony
│   ├── apt_repos/               # APT repositories & GPG keyrings
│   ├── packages/                # Base packages, DKMS tools, node-exporter
│   ├── pve_config/              # pmxcfs /etc/pve/ config templates (datacenter, storage, domains)
│   ├── kernel/                  # GRUB, modules, modprobe.d, kernel purge
│   ├── networking/              # /etc/network/interfaces
│   ├── sriov/                   # Intel X710 SR-IOV nic-sriov & iavf rebind services
│   ├── igpu_passthrough/        # iGPU vfio-pci binding verification
│   ├── dbus/                    # D-Bus reply limit
│   ├── monitoring/              # lm-sensors, rasdaemon, cron temp check
│   ├── systemd_exporter/        # Prometheus systemd_exporter
│   ├── smartctl_exporter/       # Prometheus smartctl_exporter
│   ├── alloy/                   # Grafana Alloy journal log shipper
│   ├── tailscale/               # Tailscale daemon & custom port config
│   └── pve_nag/                 # PVE subscription nag removal script
├── proxmox.yml                  # Top-level playbook
├── Makefile                     # Commands for playbook and host maintenance
└── README.md                    # This file
```
