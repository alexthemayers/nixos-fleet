# NixOS Fleet

Welcome to `nixos-fleet`, the declarative infrastructure repository managing a unified cluster of NixOS nodes, personal
workstations, cloud gateways, and home lab virtual machines.

This repository uses **Nix Flakes** to describe host architectures, **SOPS** for encrypted secret injection,
**Attic** for production activation (`nix copy --from` then `switch-to-configuration`), and a **GitLab CI**
pipeline for continuous integration and automated deployment. `deploy-rs` remains as a fallback.

---

## 🗺️ Fleet Overview

The fleet is comprised of the following nodes (defined under [`hosts/`](hosts/)):

| Node Name                   | Operating System        | Role                         | Key Services                                                                             |
|-----------------------------|-------------------------|------------------------------|------------------------------------------------------------------------------------------|
| **`truenas-scale`**         | TrueNAS Scale (Debian)  | Core NAS storage & hypervisor| ZFS, NFS, Proxmox VE (Nested)                                                            |
| **`rpi4`**                  | NixOS (aarch64-linux)   | USB backup target            | Vaultwarden replica (not edge-routed), USB backup target |
| **`xcloud-caddy`**          | NixOS (x86_64-linux)    | Cloud proxy gateway          | Caddy (edge), oauth2-proxy                                                               |
| **`xcloud-postgres`**       | NixOS (x86_64-linux)    | Cloud database               | PostgreSQL 17, PgBouncer                                                                 |
| **`proxmox-applications-1`**| NixOS (x86_64-linux)    | GPU-accelerated applications | Jellyfin, Immich, Luanti, Vaultwarden, Actual Budget, Paperless-ngx, Keycloak, Vikunja   |
| **`proxmox-applications-2`**| NixOS (x86_64-linux)    | Stateless applications       | GitLab, Container Registry, Keycloak, Paperless-ngx, Vikunja                             |
| **`proxmox-observability-1`**| NixOS (x86_64-linux)   | Central metrics & logging    | Grafana, Prometheus, Loki, Mimir, ntfy                                                   |
| **`proxmox-observability-2`**| NixOS (x86_64-linux)   | Observability replica        | Grafana, Prometheus, Loki, Mimir, ntfy                                                   |
| **`proxmox-dev`**           | NixOS (x86_64-linux)    | Compilation and builder host | Coder Server, GitLab Runner (Podman), Attic (monolithic)                                 |
| **`proxmox-db-1`**          | NixOS (x86_64-linux)    | S3 Object storage            | Garage S3 daemon                                                                         |
| **`proxmox-db-2`**          | NixOS (x86_64-linux)    | S3 Object storage            | Garage S3 daemon                                                                         |
| **`proxmox-lb`**            | NixOS (x86_64-linux)    | Internal load balancer       | Caddy (internal), UDP layer-4 proxy                                                      |
| **`gaming`**                | NixOS (x86_64-linux)    | Personal workstation         | AMD GPU and desktop configuration                                                        |

The Proxmox VE hypervisor (`proxmox` at `192.168.3.100`) is Debian, not a flake
host. It is managed from [`ansible/`](ansible/) with `make deploy-proxmox-host`.
See [docs/services/proxmox-host.md](docs/services/proxmox-host.md).

---

## 🏗️ Architectural Standards

This codebase enforces several advanced architectural patterns to ensure speed, security, and reproducibility:

1. **Strict Nix Store Leak Prevention**: Secrets decrypted at boot by `sops-nix` are injected dynamically at runtime via
   systemd `EnvironmentFile` templates or direct path references (like Grafana `$__file{}` keys) to avoid leaking
   credentials into the world-readable `/nix/store`.
2. **NFS Over-Loopback Block Storage**: High-I/O applications (like GitLab, container caches, and runners) mount sparse
   `ext4` disk images hosted on TrueNAS NFS shares via loop devices. This bypasses NFS lock latency issues and prevents
   file permission degradation.
3. **Tailscale Overlay Networking**: All internal database connections, backups, and cluster rings (Loki, Mimir,
   Keycloak) route exclusively through a trusted Tailscale network (`tailscale0`). Nodes resolve each other dynamically
   using MagicDNS.
4. **PgBouncer Dynamic Database Auth**: Client services connect to databases via PgBouncer on port `5432`. PgBouncer
   dynamically queries PostgreSQL on port `5433` using the `pg_shadow` table (`auth_query`) to verify scram-sha-256
   passwords, eliminating static credential files.
5. **UDP GRO and TCP MSS Clamping**: Tailscale traffic is optimized using custom ethtool GRO setups to reduce CPU load
   under heavy I/O, and egress packets are mangled with TCP MSS Clamping to prevent MTU black holes.

For details, see the **[Codebase Standards Document](docs/standards.md)**.

---

## 🔑 Keycloak admin console

The public IdP is `https://identity.alexmayers.co.za`. The **admin console** is
`https://identity.alexmayers.co.za/admin`. Edge Caddy `abort`s `/admin*` unless
the client source IP is in Tailscale CGNAT (`100.64.0.0/10`). There is no
oauth2-proxy on this vhost.

**A laptop with Tailscale connected is not enough.** Public DNS still points at
`xcloud-caddy`'s WAN IP, so Caddy sees your ISP address and resets the
connection.

From a workstation with Tailscale up, pin
`identity.alexmayers.co.za` to `xcloud-caddy`'s tailnet IPv4
(`tailscale ip -4 xcloud-caddy`) in `/etc/hosts`, then open the URL.
`dig` ignores `/etc/hosts`; Chrome/Firefox secure DNS can too. Full
steps, SOCKS fallback, and split DNS:
[docs/services/keycloak.md](docs/services/keycloak.md#accessing-the-admin-console).

Login is Keycloak user `admin`; the password is
`keycloak/bootstrap_admin_password` (`make edit-secrets HOST=proxmox-applications-1`).
Changing that sops value does not rotate an existing database user.

---

## 📖 Documentation Index

We maintain comprehensive documentation for all parts of the fleet inside the [`docs/`](docs/) directory:

### Core Architecture Guides

- 🔐 **[Secrets Management Architecture](docs/secrets.md)**: SOPS age configuration, host boundary boundaries, and Nix
  store leak protection patterns.
- 🚀 **[Deployments & Pipelines](docs/deployments.md)**: Attic copy + switch, GitLab fill/verify/deploy, deploy-rs fallback.
- 📐 **[Fleet Standards & Trends](docs/standards.md)**: NFS loopbacks, wait-for-host guards, PgBouncer setups, and
  Tailscale optimizations.
- ⚙️ **[Custom NixOS Options](docs/custom-options.md)**: Details on the custom `services.build-cache` and
  `fleet.waitForHost` options.
- 📊 **[Distributed Performance Monitoring](docs/monitoring.md)**: How the round-robin `iperf3-speedtest-coordinator`
  daemon collects performance metrics.
- 🧠 **[Memory limits](docs/memory.md)**: systemd `MemoryMax` / `MemoryHigh` inventory for host RAM sizing.
- 💾 **[Disk Partitioning & Bootstrap](docs/storage-disko.md)**: Declarative storage configuration using Disko and
  bootstrapping instructions.

### Host Profiles

Individual host profiles detailing workstation setups and local integrations:

- 🎮 **[gaming Workstation](docs/hosts/gaming.md)**: GPU drivers, Vulkan configurations, ratbagd, keyd, and Plasma 6
  settings.
- 🍓 **[rpi4 Backup Node](docs/hosts/rpi4.md)**: USB external backup storage and a
  Vaultwarden replica that is not in the edge path.
- 🗃️ **[xcloud-postgres Database Node](docs/hosts/xcloud-postgres.md)**: Isolated database volume configurations using
  Disko.

### Service Configurations Index

Detailed profiles explaining configuration choices, ports, storage dependencies, and keys:

| Observability & Network                                           | Apps & Databases                                  | Storage & CI/CD                                              | Media & Gaming                                   |
|:------------------------------------------------------------------|:--------------------------------------------------|:-------------------------------------------------------------|:-------------------------------------------------|
| 🔍 [Prometheus](docs/services/prometheus.md)                      | 💾 [PostgreSQL](docs/services/postgres.md)        | 📦 [Container Registry](docs/services/container-registry.md) | 🎬 [Jellyfin](docs/services/jellyfin.md)         |
| 📊 [Grafana](docs/services/grafana.md)                            | 🔑 [Keycloak](docs/services/keycloak.md)          | 🤖 [GitLab Runner](docs/services/gitlab-runner.md)           | 📸 [Immich](docs/services/immich.md)             |
| 🪵 [Loki](docs/services/loki.md)                                  | 🦊 [GitLab](docs/services/gitlab.md)              | 💾 [Garage S3](docs/services/garage.md)                      | 🕹️ [Luanti (Minetest)](docs/services/luanti.md) |
| 📈 [Mimir](docs/services/mimir.md)                                | 🔒 [Vaultwarden](docs/services/vaultwarden.md)    | 🧊 [Attic Nix Cache](docs/services/attic.md)                 | 🎮 [OpenArena](docs/services/openarena.md)       |
| 🖧 [Tailscale](docs/services/tailscale.md)                        | 🗃️ [Paperless-ngx](docs/services/paperless.md)   |                                                              |                                                  |
| 🌐 [oauth2-proxy](docs/services/oauth2-proxy.md)                  | 📋 [Vikunja](docs/services/vikunja.md)            |                                                              |                                                  |
| 🔔 [ntfy](docs/services/ntfy.md)                                  | 💰 [Actual Budget](docs/services/actualbudget.md) |                                                              |                                                  |
| 📡 [Blackbox Exporter](docs/services/blackbox-exporter.md)        | 💻 [Coder Server](docs/services/coder.md)         |                                                              |                                                  |
| ⚡ [Tailscale Exporter](docs/services/tailscale-exporter.md)       | 🧠 [Redis](docs/services/redis.md)                |                                                              |                                                  |
| 🔌 [TrueNAS Exporter](docs/services/truenas-graphite-exporter.md) |                                                   |                                                              |                                                  |
| 📝 [Caddy (edge)](docs/services/caddy.md)                         |                                                   |                                                              |                                                  |
| ⚖️ [Caddy (internal LB)](docs/services/caddy-internal.md)         |                                                   |                                                              |                                                  |

---

## 🚀 Getting Started & Deployments

System deployments **fill Attic first** (copy from a public substituter if a NAR
is missing), then copy each host closure **from Attic only** and run
`switch-to-configuration`. After fill, the builder does not use `cache.nixos.org`.
`deploy-rs` remains as `make deploy-rs` (magicRollback). `gaming` uses the same
Attic path; GitLab keeps that job manual.

### Local Execution (via Makefile)

Common commands are mapped inside the [Makefile](Makefile):

```bash
make fmt && make fmt-check
make lint
make check-inventory

# Fill current-system hosts and operator tooling into Attic (requires ATTIC_TOKEN)
make build

# Prove tooling and every host toplevel is in Attic (no cache.nixos.org, no local compile)
make verify-from-attic

# Deploy one host from Attic
make deploy-from-attic HOST=proxmox-dev

# Deploy the production fleet from Attic (rpi4 via scripts/run-on-rpi4.sh)
make deploy
```

See [docs/deployments.md](docs/deployments.md) for CI vs local diffs and the
script index. Agent do/don't: [`.cursor/rules/`](.cursor/rules/) (index in
[AGENTS.md](AGENTS.md)).

### Automated Deployments

Every merge to the `main` branch triggers GitLab CI: lint/format/inventory (no Attic token), fill Attic
when Nix/lockfile/scripts change, narinfo-check, then copy-from-Attic and switch on each production
host whose toplevel changed. Docs-only commits skip fill and deploy. GitHub Actions is lint-only.
