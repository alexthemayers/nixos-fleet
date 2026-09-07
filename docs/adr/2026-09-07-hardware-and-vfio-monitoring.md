---
status: accepted
date: 2026-09-07
---

# Hardware, VFIO, SR-IOV, and GPU Passthrough Observability

## Context and Problem Statement

The Proxmox VE hypervisor and its 8 guest VMs run hardware-dependent workloads:
Intel Arrow Lake iGPU passthrough to `proxmox-applications-1` (Jellyfin QSV and
Immich ML), Intel X710 10GbE SR-IOV VFs on `iavf` with MTU 9000 across all VMs,
and thermal/power management on consumer B860 hardware.

Before this change, VFIO binding was checked only during Ansible playbook runs,
guest SR-IOV packet drops were unalerted, CPU temperatures were only checked by a
cron script logging to journald, and GPU activity inside `proxmox-applications-1`
was completely dark.

How do we create continuous visibility and low-noise alerting over hardware,
VFIO, SR-IOV, and GPU passthrough across the hypervisor and guest VMs?

## Decision Drivers

* Low cardinality and strict adherence to Mimir series headroom (`docs/adr/2026-09-05-mimir-series-headroom.md`).
* Non-disruptive telemetry: no kernel rebuilds, driver rebinding, or hypervisor reboot.
* High alert fidelity: alerting on true failure symptoms (packet drops, thermal throttling, unbound VFIO, GPU resets).

## Considered Options

* Option 1: Custom daemon exporters with open ports and new Prometheus scrape jobs.
* Option 2: Standalone shell/python telemetry scripts running via systemd timers writing to `node-exporter` textfile directories, scraped by existing `node exporter` jobs.

## Decision Outcome

Chosen option: Option 2 (node-exporter textfile collectors and `ethtool` collector),
because it reuses existing Prometheus scrape configs, requires opening zero new ports,
adds negligible series cardinality, and runs safely decoupled from daemon lifecycles.

### Consequences

* Good: Hypervisor VFIO binding, SR-IOV VF counts, trust modes, and PF per-VF drop rates are collected every 15s and scraped at the Prometheus interval.
* Good: CPU package thermals (native `node_cpu_package_throttles_total`) and hypervisor swap I/O alert immediately into Alertmanager.
* Constraint: metrics that back a `== 0` / label-selector alert must be label-stable. `node_hardware_pci_driver_bound{device_name="igpu"}` carries no `driver` label (that would make a hijacked device emit a different series and silence `VFIODriverUnbound`); the driver string is exposed on the info metric `node_hardware_pci_driver_info`.
* Constraint: kernel-log event counters (DMAR/IOMMU faults, PCIe AER, in-guest Xe engine resets) are read from `journalctl -k -b`, not the volatile `dmesg` ring buffer, so `increase()`/`rate()` do not see phantom counter resets. PCIe AER alerting uses rasdaemon's authoritative `node_ras_aer_events_total`.
* Constraint: swap-pressure alerting gates on `node_vmstat_pswpin`/`pswpout` (actual swap I/O), not `node_vmstat_pgpgin` (all block-device page-ins).
* Good: sudden hardware-freeze failures (Sept 4 2026 Arrow Lake-S SoC fault under thermal + memory-controller stress) are now detectable after the fact and pre-emptively: `node_hardware_bert_error_records` (ACPI BERT fatal record from the prior boot), hypervisor memory-pressure and EDAC alerts for the overcommit/IMC-stress path, `gigabyte_wmi` board/VRM temps, and `node_dmi_info`/`node_cpu_microcode_info` for BIOS/microcode currency. Triage and mitigations live in [`../runbooks/proxmox-hardware-crash.md`](../runbooks/proxmox-hardware-crash.md).
* Constraint: `bert_disable` is a boolean kernel flag. Presence — including `bert_disable=0` — disables BERT parsing (`BERT: Boot Error Record Table support is disabled.`). The GRUB cmdline must omit the token. `node_hardware_bert_enabled` and `ProxmoxBERTDisabled` catch a regression.
* Good: In-guest Intel Xe DRM driver telemetry exports engine frequencies, active/sleep residency, DRM client counts, and driver resets on `proxmox-applications-1`.
* Good: Guest `iavf` packet drops and ring buffer discards alert on sustained drop rates before clients buffer.
* Good: Single unified Grafana dashboard `fleet-hardware` displays all hardware metrics and alerts.

## Validation

* `ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags packages,monitoring` deploys hypervisor telemetry.
* `hosts/proxmox-applications-1/configuration.nix` runs `intel-gpu-telemetry.timer`.
* Alerts validated in `services/mimir-rules.nix` (`hardware-hypervisor`, `sriov-network`, `gpu-acceleration`).
* Dashboard validated in `services/grafana/dashboards/fleet/fleet-hardware.json`.
