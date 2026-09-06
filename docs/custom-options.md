# Custom NixOS Options

To maintain clean configurations and handle complex mounting behaviors uniformly across the fleet, this repository
implements custom NixOS modules under the `config/` directory. This document describes the option schemas, use cases,
and underlying mechanics of these options.

---

## 📦 NFS Loopback Build Cache (`services.build-cache`)

* **Implementation:** [config/build-cache.nix](../config/build-cache.nix)
* **Use Cases:** [proxmox-applications-2](../services/container-registry.nix) (Docker/GitLab Registry caches). This is
  currently the module's only consumer.

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

* **Implementation:** [config/wait-for-host.nix](../config/wait-for-host.nix)
* **Use Cases:** Inherited by [config/basics.nix](../config/basics.nix) and applied
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

* **`host`** (string, required): Hostname or IP to reach.
* **`port`** (TCP port, optional): If set, wait for that port to accept connections. If unset, ICMP ping.
* **`maxRetries`** (int, default `600`): Wall-clock seconds to wait before failing.
* **`forServices`** (list of unit names, default `[]`): Units that `Requires=` and `After=` this wait.
  NFS mounts still use `x-systemd.requires=wait-for-host-<name>.service` instead.

Waits are **not** `wantedBy = multi-user.target`. They only run when a mount or service requires them, so VMs can boot
in any order: a host that does not need Postgres will not stall 600s if `xcloud-postgres` is still coming up.

### Systemd Integration

For each declared check, `wait-for-host-${name}.service` is created:

- `after` / `wants` `network-online.target` and `tailscaled.service`.
- `TimeoutStartSec` is `maxRetries + 30` seconds.
- Ping (`ping -c 1 -W 1`) or TCP (`nc -z -w 1 host port`), retried until success or timeout.

Presets under `fleet.waitFor.garage.<name>` and `fleet.waitFor.postgres.<name>` expand to the usual
`proxmox-db-1:3902` / `proxmox-lb:3902` and `xcloud-postgres:5432` waits.

---

## Fleet inventory (`fleet.inventory`)

* **Implementation:** [config/fleet-inventory.nix](../config/fleet-inventory.nix)

`nixosHosts` / `hosts` are the addressable name lists. `nodes.<hostname>` holds `tailscalePort` and optional
`sriovMac`. Prometheus fleet scrape jobs and `services.tailscale.port` are derived from this. Adding a NixOS
host means adding the name to `nixosHosts` **and** a `nodes` entry.

---

## Cluster gossip address (`fleet.clusterEnv`)

* **Implementation:** [config/cluster-env.nix](../config/cluster-env.nix)

Writes the host's tailscale0 IPv4 into an `EnvironmentFile` before Loki, Mimir, or Alertmanager start.
systemd loads `EnvironmentFile` before `ExecStartPre`, so this cannot be an `ExecStartPre` on the daemon.
How-to: [how-to-dynamic-tailscale.md](how-to-dynamic-tailscale.md).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service` | string | | Systemd unit that consumes the file |
| `envFile` | string | `/run/${name}-cluster.env` | Path of the generated EnvironmentFile |
| `ipVariable` | string | | Variable set to the tailscale0 IPv4 |
| `ipSuffix` | string | `""` | Appended (e.g. `:9094`) |
| `extra` | attrs of string | `{}` | Extra `KEY=value` lines |
| `timeoutSec` | int | `60` | Seconds to wait for an address |

---

## iperf3 mesh (`fleet.networkTesting`)

* **Implementation:** [config/network-testing.nix](../config/network-testing.nix)

`enable` turns on the coordinated iperf3 daemon. `config/observability.nix` sets
it on every fleet host. `rpi4` is commented out of the peer list for now
([monitoring.md](monitoring.md)).

---

## Attic role (`fleet.services.attic.mode`)

* **Implementation:** [services/attic.nix](../services/attic.nix)

`monolithic` or `api-server` (default). Exactly one host may be `monolithic`
([adr/2026-08-29-attic-monolithic.md](adr/2026-08-29-attic-monolithic.md)).
That host is `proxmox-dev`.

---

## Garage (`fleet.services.garage`)

* **Implementation:** [services/garage.nix](../services/garage.nix)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | | Garage S3 daemon |
| `dataDir` | string | `/var/lib/garage/data` | Block directory |
| `mountNfs` | bool | `false` | Mount `dataDir` from TrueNAS |
| `nfsShare` | string | `truenas-scale:/mnt/ssd/garage/data` | NFS path |
| `bootstrapS3` | bool | `false` | Create buckets/keys on this node |

Do not `chown` meta to `garage`. S3 clients use `proxmox-lb:3902`.

---

## Redis (`fleet.services.redis`)

* **Implementation:** [services/redis.nix](../services/redis.nix)

`enable` starts the oauth2-proxy, vikunja, and paperless Redis instances on
`xcloud-postgres`. Passwords are sops files, not Nix strings.

---

## Disko disk path (`fleet.disk.path`)

* **Implementation:** [disko/disk-config.nix](../disko/disk-config.nix)

String path of the boot disk for the shared GPT layout. Hosts set this to the
device Disko should partition.

---

## Shared NFS automount options

* **Implementation:** [config/nfs-mount.nix](../config/nfs-mount.nix)

A function, not a module: `import ../config/nfs-mount.nix "paperless" [ ]`. Do not use it for GitLab state
(must not idle-unmount).
