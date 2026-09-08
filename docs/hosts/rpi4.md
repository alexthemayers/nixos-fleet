# Raspberry Pi 4 Profile: `rpi4`

This document details the configuration, backup management, and deployment strategy for the **`rpi4`** node, which
serves as the local USB backup target. It is not an edge failover.

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
# Host-only fill (skip compiling the aarch64 deploy-rs devShell):
ATTIC_SKIP_TOOLING=1 ./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh rpi4
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

The Pi is the USB backup target. Vaultwarden still runs here and Syncthing
replicates `/var/lib/vaultwarden` from apps-1; edge Caddy does not fail over
to `rpi4:8222`. It runs the usual node/systemd exporters and Vector. It does
**not** run blackbox (that is obs-1), Keycloak, Grafana, Prometheus, Loki,
Mimir, ntfy, or Garage. Garage's live layout is db-1 + db-2 only.

A stale 2026-07-24 generation still had those daemons (`Restart=always`). Loki crash-looped on S3
`DeleteObject` 403 and rejoined obs memberlist under a new `loki-v4-rpi4-<id>` each time (~1.7k ghosts).
[hosts/rpi4/configuration.nix](../../hosts/rpi4/configuration.nix) **masks** the leftover units (including
`prometheus-blackbox-exporter`) so a switch stops them instead of letting systemd start the old files. Do **not** restart obs Loki until the Pi Loki
unit is `dead` (it will refill the ring). Then restart obs Loki and check
`curl -sS http://127.0.0.1:3100/memberlist` shows **Members: 2**.

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

