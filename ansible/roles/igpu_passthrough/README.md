# iGPU Passthrough — Intel Arrow Lake-S (8086:7d67)

This document explains how Intel iGPU passthrough is configured on the Proxmox VE host.

---

## Hardware

| Property        | Value                                    |
|-----------------|------------------------------------------|
| CPU             | Intel Arrow Lake-S                       |
| iGPU            | Intel Arc Graphics (Arrow Lake-S)        |
| PCI ID          | `0000:00:02.0`                           |
| Device ID       | `8086:7d67`                              |
| Motherboard     | Gigabyte B860I AORUS PRO ICE             |
| IOMMU           | Intel VT-d (enabled via BIOS + kernel)   |

---

## How It Works

### 1. IOMMU Setup

The kernel command line (managed by the `kernel` role via `/etc/default/grub`) includes:

```
intel_iommu=on   — Enable Intel VT-d IOMMU
iommu=pt         — Passthrough mode: bypass IOMMU for DMA-capable devices not assigned to VMs.
                   Reduces overhead for non-passthrough devices.
```

These parameters are set in `group_vars/all/vars.yml` under `grub_cmdline`.

### 2. Host Driver Blacklisting

`/etc/modprobe.d/vfio-gpu.conf` (managed by the `kernel` role) blacklists the two Intel GPU drivers:

```
blacklist i915   — Intel Gen12+ integrated graphics driver
blacklist xe     — Newer Intel GPU driver (intended replacement for i915 on recent hardware)
```

Additionally, `xe` is blacklisted at the GRUB level via `module_blacklist=xe` in the kernel command line as a belt-and-suspenders measure, because `xe` can load before `modprobe.d` is processed in some initrd configurations.

### 3. vfio-pci Binding

`/etc/modprobe.d/vfio-gpu.conf` also configures `vfio-pci` to claim the device:

```
options vfio-pci ids=8086:7d67
```

This ensures that when the PCI device `0000:00:02.0` is probed at boot, `vfio-pci` claims it before any host GPU driver can bind to it.

### 4. Unsafe Interrupts

```
options vfio_iommu_type1 allow_unsafe_interrupts=1
```

Consumer-grade motherboards (including this B860I board) do not implement ACS (Access Control Services) for all PCIe slots, which means some devices share IOMMU groups. `allow_unsafe_interrupts=1` is required to pass through a device that shares its IOMMU group with another host device.

### 5. i915 GVT Kernel Parameters

The kernel command line includes parameters that configure the i915 driver's behaviour, even though i915 is blacklisted on the host. These matter if i915 is ever re-enabled, and for SR-IOV virtual function behaviour:

| Parameter              | Value | Meaning                                                                          |
|------------------------|-------|----------------------------------------------------------------------------------|
| `i915.enable_guc=3`    | 3     | Enable GuC submission + HuC firmware loading. Required for stable SR-IOV iGPU.  |
| `i915.max_vfs=3`       | 3     | Allow up to 3 SR-IOV Virtual Functions from the iGPU (for future use).          |
| `i915.force_probe=7d67`| 7d67  | Force i915 to probe this device ID (Arrow Lake not yet in stable ID table).      |

---

## Which VMs Use the iGPU

| VM  | Name                         | Config                                    |
|-----|------------------------------|-------------------------------------------|
| 101 | `proxmox-applications-1`     | `hostpci1: 0000:00:02.0,pcie=1,rombar=0` |

The VM uses **full PCI passthrough** (not GVT-g or SR-IOV vGPU). The entire physical iGPU is exclusively assigned to VM 101.

---

## GVT-d vs Full Passthrough

This setup uses **GVT-d** (Intel Graphics Virtualization Technology — direct assignment), also called full passthrough:

- The iGPU is bound to `vfio-pci` and passed directly to one VM.
- Only one VM can use the iGPU at a time.
- The host has **no display output** from the iGPU.

This is distinct from **GVT-g** (mediated passthrough), which would allow multiple VMs to share the GPU via virtual GPU (vGPU) instances. GVT-g is not used here because Arrow Lake support in the i915 driver is not yet stable enough for mediated passthrough.

---

## VM BIOS Requirement

The VM **must** use **OVMF (UEFI)** as its BIOS. SeaBIOS (the default Proxmox BIOS) does not support PCI passthrough for modern iGPUs. In the Proxmox VM config:

```
bios: ovmf
machine: q35
```

The Q35 machine type is also required for proper PCIe topology.

---

## Verification

After reboot, verify the iGPU is correctly bound:

```bash
lspci -k -s 00:02.0
```

Expected output:
```
00:02.0 Display controller: Intel Corporation Device 7d67 (rev 08)
        Subsystem: Gigabyte Technology Co., Ltd Device 5000
        Kernel driver in use: vfio-pci
        Kernel modules: i915, xe
```

The key line is `Kernel driver in use: vfio-pci`. If this shows `i915` or `xe` instead, the blacklist has not taken effect — rebuild the initrd (`update-initramfs -u -k all`) and reboot.

The `igpu_passthrough` Ansible role also asserts this condition and will fail the playbook run with a clear error message if the binding is wrong.

---

## Troubleshooting

| Symptom                              | Cause                                         | Fix                                              |
|--------------------------------------|-----------------------------------------------|--------------------------------------------------|
| `Kernel driver in use: i915`         | Blacklist not applied in initrd               | `update-initramfs -u -k all` then reboot         |
| `Kernel driver in use: xe`           | `xe` module loaded before blacklist           | Add `module_blacklist=xe` to GRUB cmdline        |
| VM fails to start with PCIe error    | IOMMU group conflict                          | Set `allow_unsafe_interrupts=1`                  |
| VM starts but no GPU visible         | Wrong PCI ID in VM config or ROM issue        | Check `hostpci1` in VM conf, try `rombar=0`      |
| Host has no display after reboot     | Expected — host drivers are blacklisted       | Use SSH/web UI only                              |
