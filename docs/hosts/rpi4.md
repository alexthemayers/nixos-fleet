# Raspberry Pi 4 Profile: `rpi4`

This document details the configuration, backup management, and deployment strategy for the **`rpi4`** node, which
serves as the local backup storage repository and high-availability failover host.

---

## Hardware and build

* **Platform:** 64-bit ARM (`aarch64-linux`), using
  [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).
* **System Tags:** [tags.nix](../../hosts/rpi4/tags.nix) exports hardware identifiers
  to the system generation.

### Native compilation on the Pi

`rpi4` is `remoteBuild = false` in [flake.nix](../../flake.nix) for the deploy-rs
fallback. Production fill and activation run **on the Pi**:

```bash
./scripts/run-on-rpi4.sh ./scripts/build.sh
./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh rpi4
# or:
make build-rpi
make deploy-rpi
```

Do not qemu-compile aarch64 on `proxmox-dev` or `proxmox-applications-2`. GitLab
`fill-attic-rpi4` / `verify-from-attic-rpi4` / `deploy-rpi4` ssh into this host
and run the same scripts. See
[adr/2026-08-31-rpi4-native-build.md](../adr/2026-08-31-rpi4-native-build.md).

---

## Failover

The Pi is the USB backup target and a **Vaultwarden** edge replica (Caddy fails over to `rpi4:8222`). It also
runs the fleet's only blackbox prober. It does **not** run Keycloak, Grafana, Prometheus, Loki, Mimir, ntfy,
or Garage: those imports were dropped, and Garage's live layout is db-1 + db-2 only.

---

## USB backup

* **Implementation:** [usb-backup-mount.nix](../../hosts/rpi4/usb-backup-mount.nix)

A high-capacity external USB drive is mounted at `/mnt/usb-backup`. The mount is
fail-closed (no `nofail`): if the disk is missing, activation fails rather than
writing backups onto the SD card.

systemd tmpfiles:

* `/mnt/usb-backup/postgres_backups` — drop files older than 30 days
* `/mnt/usb-backup/gitlab_backups` — drop files older than 14 days

`alex` on this host accepts the `xcloud-postgres` backup SSH key so SQL dumps
can land here without an interactive login.

