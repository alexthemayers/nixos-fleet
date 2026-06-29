# Codebase Standards & Trends

This document summarizes the architectural patterns, trends, and standards observed across the `nixos-fleet` codebase.

---

## 1. Secrets Security (Nix Store Leak Prevention)

Nix compiles configurations into `/nix/store`, which is world-readable by any local user. To prevent plaintext
credentials from leaking into the store, services in this fleet strictly apply one of three methods:

- **Environment File Injection**: Creating templates using `sops.templates` and referencing them via systemd
  `EnvironmentFile`.
- **Reference by Path**: Referencing the decrypted secret file path dynamically using application features like
  Grafana's `$__file{}` command.
- **Runtime Shell/Ruby Script Reading**: Using inline scripts to read files at process launch time (such as GitLab's
  `<%= File.read(...) %>` tag).

---

## 2. NFS Over-Loopback Block Devices (`build-cache.nix`)

Running high-concurrency, high-I/O applications (like container registries, GitLab, or Nix builds) directly on raw NFS
directories leads to lock contention, file permission conflicts, and slow speed.

To address this, the fleet uses a loopback mechanism
in [config/build-cache.nix](file:///Users/alex/code/nixos-fleet/config/build-cache.nix):

- It mounts an NFS directory from TrueNAS.
- It creates a large sparse disk image (e.g. `50G` or `100G`) using `truncate` and formats it as an `ext4` filesystem.
- It mounts that sparse image file locally via a loop device (`mount -o loop`).
- **Benefit**: This combines the durability and size of remote storage with the performance, locking mechanisms, and
  permission isolation of a local ext4 block device.

---

## 3. Storage Availability Guards (`fleet.waitForHost`)

Because hosts mount directories from `truenas-scale` over the Tailscale network, a boot-time race condition exists: if
mounts are attempted before Tailscale connects or before the NAS is online, the host may crash, hang, or drop into
emergency mode.

The fleet addresses this with `fleet.waitForHost`
in [config/wait-for-host.nix](file:///Users/alex/code/nixos-fleet/config/wait-for-host.nix):

- Defines systemd oneshot services (`wait-for-host-<name>`) that run `ping` loops targeting the NAS.
- Systemd file system mounts declare `x-systemd.requires=wait-for-host-<name>.service` to ensure mounting only occurs
  after connectivity is verified.

---

## 4. PgBouncer Dynamic Auth & Connection Isolation

To ensure high database connection efficiency:

- PostgreSQL listens on port **5433** (TCP access restricted to localhost/peer/Tailscale).
- PgBouncer listens on the standard port **5432** to handle pooling (transaction pooling for most, session pooling for
  Immich and Coder).
- **Dynamic Auth**: PgBouncer is configured with
  `auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1"`. Instead of maintaining database user
  passwords in static text files, PgBouncer dynamically queries PostgreSQL to verify passwords securely utilizing
  `scram-sha-256`.

---

## 5. Dynamic Tailscale Gossip IP Resolution

Clustered systems (Loki, Mimir, Keycloak) require nodes to peer with each other over the Tailscale network. Since
Tailscale IPs are dynamically allocated, hardcoding IPs in configurations would break deployments.

To solve this, systemd launch configurations use custom `ExecStart` wrappers to query the local `tailscale0` IP address
at startup:

```bash
TAILSCALE_IP=$(ip -4 addr show dev tailscale0 | awk '/inet / {print $2}' | cut -d/ -f1)
```

This IP is then exported as an environment variable and injected into the service configurations (e.g., Loki/Mimir
memberlist gossip and Keycloak clustering).

---

## 6. Rootless Podman & Pull-Through Registry Caches

To save external bandwidth and accelerate development pipelines:

- The container registry server runs local registry caches (Docker Hub, GHCR, Quay, GCR) inside rootless Podman
  containers managed under the `docker-registry` system user.
- Hosts globally rewrite `/etc/containers/registries.conf` to configure mirrors routing through these caches.
- Regular garbage collection of cached layers is run automatically on Sundays via oneshot systemd services.

---

## 7. Systemd Sandboxing Overlays

Standard NixOS service configurations are reinforced with custom overlays:

- **`BindPaths`**: Restricting service file access by mapping external mount directories into the service's sandbox.
- **`TimeoutStopSec = "15s"`**: Restricting wait times on service shutdown (crucial for services like Jellyfin that can
  hang on termination).
- **`SupplementaryGroups`**: Adding service daemons to helper groups (like `keys` or `render`) to grant access to
  credentials or GPU transcoding units.
