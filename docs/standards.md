# Codebase Standards & Trends

This document summarizes the architectural patterns, trends, and standards observed across the `nixos-fleet` codebase.

---

## 0. Zero technical debt

Attitude from TigerBeetle
[TigerStyle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md):
do it right the first time. What ships meets the bar. Missing features are
fine; half-done quality is not. Agent constraint:
[`.cursor/rules/zero-debt.mdc`](../.cursor/rules/zero-debt.mdc).

- Do not leave known defects, vacuous guards, or stale operator docs in a
  merged change.
- A check that always passes over empty data is not a check.
- **No CI validation for a given piece of load-bearing code is debt.** If
  it can break production, GitLab CI must fail when it is wrong. Prefer
  extending `make lint`, `ansible-lint`, or a dedicated `make check-*`
  wired into [`.gitlab-ci.yml`](../.gitlab-ci.yml). Darwin may skip
  x86_64-only binaries locally when CI on the builder still runs them
  ([deployments.md](deployments.md)).
- Accepted ADR freezes are decisions, not debt.

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

## 2. NFS Over-Loopback Block Devices

Running high-concurrency, high-I/O applications (like container
registries or GitLab) directly on raw NFS leads to lock contention and
slow writes. The Debian GitLab guest mounts sparse ext4 images from NFS
via the `fleet.debian_guest` gitlab and registry_cache roles
([container-registry.md](services/container-registry.md),
[custom-options.md](custom-options.md)).

Garage and Mimir are decommissioned
([decommission-garage](adr/2026-11-06-decommission-garage.md)).

---

## 3. Storage Availability Guards (`fleet.waitForHost`)

Because hosts mount directories from `truenas-scale` over the Tailscale network, a boot-time race condition exists: if
mounts are attempted before Tailscale connects or before the NAS is online, the host may crash, hang, or drop into
emergency mode.

The fleet addresses this with `fleet.waitForHost` defined in [config/wait-for-host.nix](../config/wait-for-host.nix) (
documented in the **[Custom NixOS Options Guide](custom-options.md)**):

- Defines systemd oneshot services (`wait-for-host-<name>`) that ping or TCP-probe a dependency for up to 600s.
- NFS mounts use `x-systemd.requires=wait-for-host-<name>.service`. Services that talk to Postgres, Redis, or
  GitLab set `forServices` so they do not start until that port is open. VMs can therefore boot in any order.
  Prefer `fleet.waitFor.postgres` / `fleet.waitForHost` presets
  ([custom-options.md](custom-options.md)).

---

## 4. PgBouncer Dynamic Auth & Connection Isolation

To ensure high database connection efficiency:

- PostgreSQL listens on port **5433** (TCP access restricted to localhost/peer/Tailscale).
- PgBouncer listens on the standard port **5432** to handle pooling (transaction pooling for most, session pooling for
  Immich and Vikunja). Pool sizes are in [postgres.md](services/postgres.md).
- **Dynamic Auth**: PgBouncer is configured with `auth_type = "scram-sha-256"` and
  `auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1"`. Instead of maintaining database user
  passwords in static text files, PgBouncer dynamically queries PostgreSQL to verify passwords securely utilizing
  `scram-sha-256`.

---

## 5. Dynamic Tailscale Gossip IP Resolution

Clustered systems (Keycloak) require nodes to peer with each other over the Tailscale network. Since
Tailscale IPs are dynamically allocated, hardcoding IPs in configurations would break deployments.

To solve this, systemd launch configurations use custom `ExecStart` wrappers to query the local `tailscale0` IP address
at startup:

```bash
TAILSCALE_IP=$(ip -4 addr show dev tailscale0 | awk '/inet / {print $2}' | cut -d/ -f1)
```

This IP is then exported as an environment variable and injected into the service configurations (e.g., Keycloak clustering).

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

---

## 8. Reverse Proxy Architecture (Caddy)

Edge routing is centralized on `xcloud-caddy`. This is not a blocking WAF cluster
and not an HA pair for every app.

- **Upstreams**: edge Caddy proxies each vhost to the serving VM. There is
  no internal load balancer. See
  [adr/2026-09-07-no-internal-lb.md](adr/2026-09-07-no-internal-lb.md) and
  [adr/2026-09-06-vaultwarden-no-edge-failover.md](adr/2026-09-06-vaultwarden-no-edge-failover.md).
- **Web Application Firewall**: Coraza + OWASP CRS runs in **DetectionOnly**.
  Matches are logged; they do not block. Some media/WebSocket paths omit the WAF
  snippet. See [adr/2026-08-29-waf-detection-only.md](adr/2026-08-29-waf-detection-only.md).
- **Tier-Based Rate Limiting**: `rate_limit` zones (`limit_standard`,
  `limit_heavy`, `limit_ultra_heavy`).
- **Forward Authentication**: `forwardAuth` / `hybridForwardAuth` are **per
  vhost**. oauth2-proxy is not fleet-wide. Keycloak has no forward-auth (it is
  the IdP). See [adr/2026-08-29-oauth2-proxy-coverage.md](adr/2026-08-29-oauth2-proxy-coverage.md).

---

## 9. Database Initialization Guards (PostgreSQL)

When configuring complex services (like Immich or GitLab) that require specific extensions, schemas, or role
configurations, the fleet favors dedicated initialization scripts instead of modifying the global NixOS
`ensureDatabases` primitives, which can be limited in flexibility.

- A custom systemd `oneshot` service (`postgresql-custom-setup.service`) relies on `RemainAfterExit = true` and
  `Requires = [ "postgresql.service" ]`.
- It executes a polling loop via `psql` to wait until the database daemon is fully online and responsive.
- It then executes raw SQL statements (`CREATE EXTENSION`, `ALTER SCHEMA`) or applies passwords queried directly from
  SOPS secret files.

---

## 10. Remote Backups over SSH (`postgresqlBackup`)

Stateful components must be backed up off-site. The standard pattern implemented within the fleet leverages native NixOS
backup options augmented with SSH integrations:

- NixOS modules like `services.postgresqlBackup` handle the native data extraction (e.g., compressed `zstd` dumps).
- A `postStart` script uses `rsync -avz -e "ssh -i <sops-path> -o StrictHostKeyChecking=accept-new"` to automatically
  push the backup artifacts to `backup-relay@proxmox-dev:/var/backup-relay/`.
- This isolates backup credentials via SOPS and ensures that backups are resilient to local hardware failures.
