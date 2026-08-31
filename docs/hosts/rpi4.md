# Raspberry Pi 4 Profile: `rpi4`

This document details the configuration, backup management, and deployment strategy for the **`rpi4`** node, which
serves as the local backup storage repository and high-availability failover host.

---

## 🏗️ Hardware and Remote Build Strategy

* **Platform:** 64-bit ARM architecture (`aarch64-linux`), utilizing the out-of-tree hardware
  flake [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).
* **System Tags:** Configured dynamically in [tags.nix](../../hosts/rpi4/tags.nix) to
  export hardware identifiers (e.g. Raspberry Pi version, active bootloader, and kernel versions) to the NixOS system
  generation attributes.

### Remote Compilation

To bypass the processor limitations and thermal constraints of the Raspberry Pi 4, its deployment is configured
inside [flake.nix](../../flake.nix) with `remoteBuild = true`.

When `deploy-rs` runs a compilation:

1. The GitLab CI builder (running on **`proxmox-dev`**) compiles the ARM64 closure locally using multi-architecture
   translation (via `qemu-aarch64`).
2. The resulting closure path in the Nix store is copied directly over the local network to the Pi.
3. The activation script is executed on the Pi to switch to the new generation.

---

## 🔄 Failover Redundancy

The Pi is the USB backup target and a **Vaultwarden** edge replica (Caddy fails over to `rpi4:8222`). It also
runs the fleet's only blackbox prober. It does **not** run Keycloak, Grafana, Prometheus, Loki, Mimir, ntfy,
or Garage: those imports were dropped, and Garage's live layout is db-1 + db-2 only.

---

## 💾 USB Backup Storage Management

* **Implementation:** [usb-backup-mount.nix](../../hosts/rpi4/usb-backup-mount.nix)

The main purpose of the node is hosting the physical backup vaults. A high-capacity external USB drive is connected and
managed by the system:

1. **Mount Configuration:** Mounted at `/mnt/usb-backup` using `nofail` and a `5s` systemd device timeout to prevent
   system boot hangs if the drive is disconnected.
2. **Backup Dump Directory Retention:** Runs systemd tmpfiles cleanup rules to enforce strict retention policies on
   incoming database dumps:
    * `/mnt/usb-backup/postgres_backups`: Cleaned of files older than **30 days** (`30d`).
    * `/mnt/usb-backup/gitlab_backups`: Cleaned of files older than **14 days** (`14d`).
3. **Secure Backup Injection:** Adds SSH key configurations allowing automated cron jobs running on **`xcloud-postgres`
   ** to log in securely and transfer SQL dumps without administrative intervention.
