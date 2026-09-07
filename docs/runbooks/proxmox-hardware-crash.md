# Proxmox unexplained hard reset / hardware crash

Triage for an instantaneous freeze or power-cut on the `proxmox` hypervisor: no
kernel panic, no OOM trace, no graceful shutdown, ~90 s of downtime while UEFI
POSTs and retrains memory. Root-caused once to a fatal Intel Arrow Lake-S SoC
fault under thermal + memory-controller stress (Sept 4 2026).

> Warnings
>
> - Reading `/dev/mem` is intrusive. Do it read-only, never write.
> - Do not clear the ACPI BERT record until you have decoded it. A clean
>   reboot is what clears it, so capture first.
> - Do not raise VM RAM commit or ZFS ARC while the box is memory-saturated
>   (see [memory.md](../memory.md)). This host runs ~95% committed.
> - BIOS/microcode and power-profile changes need a reboot and a maintenance
>   window; they are not `switch-to-configuration` changes.

## Symptoms and what fires

| Signal | Alert |
|--------|-------|
| Firmware wrote a fatal error record for the last boot | `ProxmoxHardwareErrorBERT` |
| Kernel is not parsing ACPI BERT (`bert_disable` on cmdline) | `ProxmoxBERTDisabled` |
| Sustained CPU package heat soak before the crash | `ProxmoxCPUTemperatureHigh` / `Critical` |
| Thermal throttling active | `ProxmoxCPUThrottlingActive` |
| Memory near exhaustion (overcommit) | `ProxmoxMemoryPressureHigh` / `Critical` |
| Swap thrashing | `ProxmoxHostSwapping` |
| Memory-controller (EDAC) errors | `HardwareMemoryControllerErrors` |
| MCE / PCIe AER logged | `HardwareMCEError` / `PCIeAERErrorsHigh` |
| Board/VRM sensor heat soak | `ProxmoxBoardSensorHot` |
| Stale, unstable firmware | `ProxmoxBIOSOutdated` |

Dashboard: `fleet-hardware`. All rules:
[`services/mimir-rules.nix`](../../services/mimir-rules.nix).

## 1. Confirm it was a hardware crash, not software

```bash
journalctl -k -b | grep -iE 'BERT|hardware error'
```

`BERT: [Hardware Error]` plus `BERT: Total records found: N` (N > 0) means the
firmware captured a fatal error for the boot that just ended. The telemetry
exporter surfaces this as `node_hardware_bert_error_records`. No BERT record
plus an abrupt journal cut-off (last lines mid-operation, no shutdown
sequence) still points at a power/hardware event rather than the OS.

`BERT: Boot Error Record Table support is disabled.` means the kernel is not
parsing BERT at all. `bert_disable` is a **boolean** cmdline flag: presence
disables it, including `bert_disable=0`. Remove the token from
`grub_cmdline` in `ansible/group_vars/all/vars.yml`, run the kernel role,
and reboot. Until then `ProxmoxHardwareErrorBERT` cannot fire.
`node_hardware_bert_enabled == 0` pages as `ProxmoxBERTDisabled`.

The kernel role's `update-grub` handler only rewrites the boot entry; the
cmdline takes effect on the next boot. Rebooting the hypervisor restarts
every guest, so schedule it in a maintenance window — and expect
`ProxmoxBERTDisabled` to stay firing from the moment the monitoring role
ships the metric until that reboot.

## 2. Decode the BERT / CPER payload

The AMI/Gigabyte firmware may leave the Generic Error Status Block valid bit
(`ACPI_HEST_STATUS_ERR_DATA_VALID`, bit 0 of `block_status`) unset, so the
kernel skips parsing and logs `Skipped 1 error records`. Read the region
directly.

```bash
# Boot Error Region address is in the BERT table:
cat /sys/firmware/acpi/tables/BERT | xxd | head
# Map and dump the error region (read-only) at the declared address, then
# walk the CPER section headers (GUIDs) and severities.
```

Section Type GUID `81212a96-09ed-4996-9471-8d729c8e69ed` is a UEFI firmware
error reference; embedded `8f87f311-c998-4d9e-a0c4-6065518c4f6d` is an Intel
SoC CrashLog (processor context corrupt, `PCC=1`) — an uncorrectable
package-level fault the CPU could not hand to an OS `#MC` handler. That is a
platform fault, not a kernel bug.

## 3. Read the thermal and memory context around the crash

```bash
# 5-minute CPU temperature log:
grep -i temp /var/log/syslog | tail -n 60         # or the check-temps.sh output
```

Look for a sustained high-temperature soak (e.g. 82–86 °C for 15–30 min) and a
crash within ~90 s of load release — Arrow Lake-S is prone to Vdroop / C-state
lockups on load-release transients after a heat soak. In Grafana check
`node_hwmon_temp_celsius` (coretemp + `gigabyte_wmi` board sensors) and the
hypervisor memory panel. This box commits ~82 GiB of VM RAM + ~9.4 GiB ZFS ARC
on 96 GiB (~95%); near-exhaustion drives IMC/VRM stress.

## 4. Recover

The host reboots itself. Confirm VMs came back (`qm list`), Garage/Postgres
hubs are healthy, and that the BERT alert is the only lingering page. It stays
firing until the next clean reboot clears the record.

## 5. Mitigate (maintenance window)

1. Flash the motherboard BIOS from `F6` to `>= F8` (current Arrow Lake-S
   microcode and power-delivery fixes). `ProxmoxBIOSOutdated` tracks this.
2. Set the Intel Default / Baseline power profile in BIOS (disable Gigabyte
   multi-core enhancement / uncapped power limits).
3. If memory instability persists, drop DDR5 from 5600 MT/s toward JEDEC
   5200 MT/s (or nudge SoC/IMC VDD). `HardwareMemoryControllerErrors` tracks
   IMC errors.
4. Improve Mini-ITX case exhaust / fan curves to cut VRM heat soak.
   `ProxmoxBoardSensorHot` and the thermal alerts track this.
5. Reduce RAM overcommit if `ProxmoxMemoryPressure*` fires: trim VM RAM or
   `zfs_arc_max` ([memory.md](../memory.md)).
