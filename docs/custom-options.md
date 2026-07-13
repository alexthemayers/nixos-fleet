# Custom NixOS Options

To maintain clean configurations and handle complex mounting behaviors uniformly across the fleet, this repository
implements custom NixOS modules under the `config/` directory. This document describes the option schemas, use cases,
and underlying mechanics of these options.

---

## 📦 NFS Loopback Build Cache (`services.build-cache`)

* **Implementation:** [config/build-cache.nix](file:///Users/alex/code/nixos-fleet/config/build-cache.nix)
* **Use Cases:** [proxmox-dev](file:///Users/alex/code/nixos-fleet/hosts/proxmox-dev/buildcache.nix) (Nix compiler
  builds), [proxmox-applications-2](file:///Users/alex/code/nixos-fleet/services/container-registry.nix) (Docker/GitLab
  Registry
  caches).

### The Problem

High-concurrency, high-I/O applications (like compiler builders and container registries) degrade when run directly on
raw NFS directories. This is due to NFS file lock latency, permission mapping limitations, and database lock issues.

### The Solution

Instead of writing files directly to NFS, the host mounts the remote NFS share and creates a large, empty sparse file (
image). This sparse image is formatted as a local `ext4` filesystem and mounted via a loopback device (`mount -o loop`).

This provides:

1. **Isolation:** Native ext4 locking mechanisms and file permissions are fully preserved.
2. **Performance:** Bypasses NFS file lock latency.
3. **Flexibility:** Storage is stored durably on the central SAN (TrueNAS) but acts like a local block device.

### Configuration Schema

Options are defined under `services.build-cache.attachments.<name>`:

| Option                 | Type    | Default            | Description                                                             |
|:-----------------------|:--------|:-------------------|:------------------------------------------------------------------------|
| `enable`               | boolean | `false`            | Enables the loopback cache attachment.                                  |
| `nfsDevice`            | string  |                    | The NFS share path (e.g. `truenas-scale:/mnt/ssd/buildcache`).          |
| `nfsMountPoint`        | string  | `/mnt/nfs/${name}` | Temporary host path where the NFS share is mounted.                     |
| `imageName`            | string  | `${name}.img`      | Filename of the loopback image inside the NFS mount.                    |
| `imageSize`            | string  | `100G`             | Declared virtual size of the sparse image (e.g., `50G`, `100G`).        |
| `targetMountPoint`     | string  |                    | Final host path where the loopback ext4 volume will be mounted.         |
| `owner`                | string  | `root`             | System user owner of the target directory.                              |
| `group`                | string  | `root`             | System group owner of the target directory.                             |
| `mode`                 | string  | `1775`             | Permissions mode of the target directory.                               |
| `nixDaemonIntegration` | boolean | `false`            | Configures `nix-daemon` to use this mount for build execution `TMPDIR`. |

### Systemd Automation Mechanics

When an attachment is enabled, the module dynamically generates the following systemd services and mounts:

1. **NFS Mount unit (`<nfsMountPoint>.mount`):**
   Automatically generated, declaring wait-for-host guards:
   `x-systemd.requires=wait-for-host-${name}.service`
2. **Image Initialization Service (`nix-build-img-init-${name}`):**
   Runs once after the NFS mount is online. If the sparse file does not exist, it runs `truncate` and `mkfs.ext4`. If it
   does exist, it runs `e2fsck` checks and calls `resize2fs` to dynamically match the configured size.
3. **Loopback Mount unit (`<targetMountPoint>.mount`):**
   Mounts the loop device after initialization runs.
4. **Permissions Service (`nix-build-permissions-${name}`):**
   Enforces `chown` and `chmod` constraints on the final target directory.

---

## 📡 Storage Availability Guards (`fleet.waitForHost`)

* **Implementation:** [config/wait-for-host.nix](file:///Users/alex/code/nixos-fleet/config/wait-for-host.nix)
* **Use Cases:** Inherited by [config/basics.nix](file:///Users/alex/code/nixos-fleet/config/basics.nix) and applied
  globally to all nodes.

### The Problem

Since the fleet mounts remote directories over the network (specifically via the Tailscale overlay network), a boot-time
race condition exists. If systemd attempts to mount NFS shares before the network card is fully online, before Tailscale
registers, or before the target NAS is reachable, the mount fails. This can result in system boots dropping into
emergency mode.

### The Solution

The `fleet.waitForHost` module declares dependency-aware ping checkpoints. It creates oneshot systemd services that
block target mounts until connectivity to the destination IP/hostname is verified.

### Configuration Schema

Options are defined under `fleet.waitForHost.<name>`:

* **`host`** (string, required): Hostname or IP address to ping.
* **`maxRetries`** (int, default `600`): Maximum ping loops (1 attempt per second) before failing.

### Systemd Integration

For each declared host check, a systemd service `wait-for-host-${name}.service` is created:

- It runs `after = [ "network-online.target" "tailscaled.service" ]`.
- It executes a loop using `ping -c 1 -W 1 "${host}"`.
- Any systemd filesystem mount that requires this host adds the option:
  `x-systemd.requires=wait-for-host-${name}.service`
