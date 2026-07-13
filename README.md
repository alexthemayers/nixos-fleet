# NixOS Fleet

Welcome to `nixos-fleet`, the declarative infrastructure repository managing a unified cluster of NixOS nodes, personal
workstations, cloud gateways, and home lab virtual machines.

This repository uses **Nix Flakes** to describe host architectures, **SOPS** for encrypted secret injection,
**deploy-rs** for system activation, and a **GitLab CI** pipeline for continuous integration and automated deployment.

---

## 🗺️ Fleet Overview

The fleet is comprised of the following nodes (defined under [`hosts/`](hosts/)):

| Node Name                   | Operating System        | Role                         | Key Services                                                                             |
|-----------------------------|-------------------------|------------------------------|------------------------------------------------------------------------------------------|
| **`truenas-scale`**         | TrueNAS Scale (Debian)  | Core NAS storage & hypervisor| ZFS, NFS, Proxmox VE (Nested)                                                            |
| **`rpi4`**                  | NixOS (aarch64-linux)   | External gateway & failover  | Wireguard, Dynamic DNS, Failover Replicas (Identity, Vault, Gitlab)                      |
| **`xcloud-caddy`**          | NixOS (x86_64-linux)    | Cloud proxy gateway          | Caddy, oauth2-proxy, Fail2ban                                                            |
| **`xcloud-postgres`**       | NixOS (x86_64-linux)    | Cloud database               | PostgreSQL 17, PgBouncer                                                                 |
| **`proxmox-applications-1`**| NixOS (x86_64-linux)    | GPU-accelerated applications | Jellyfin, Immich, Luanti, Vaultwarden, Actual Budget, Paperless-ngx, Keycloak, Vikunja   |
| **`proxmox-applications-2`**| NixOS (x86_64-linux)    | Stateless applications       | GitLab, Container Registry, Keycloak, Paperless-ngx, Vikunja                             |
| **`proxmox-observability-1`**| NixOS (x86_64-linux)   | Central metrics & logging    | Grafana, Prometheus, Loki, Mimir, ntfy                                                   |
| **`proxmox-observability-2`**| NixOS (x86_64-linux)   | HA metrics & logging         | Grafana, Prometheus, Loki, Mimir, ntfy                                                   |
| **`proxmox-dev`**           | NixOS (x86_64-linux)    | Compilation and builder host | Coder Server, GitLab Runner (Podman)                                                     |
| **`proxmox-db-1`**          | NixOS (x86_64-linux)    | S3 Object storage            | Garage S3 daemon                                                                         |
| **`proxmox-db-2`**          | NixOS (x86_64-linux)    | S3 Object storage            | Garage S3 daemon                                                                         |
| **`proxmox-lb`**            | NixOS (x86_64-linux)    | Local Load Balancer          | Tailscale Subnet Router                                                                  |
| **`gaming`**                | NixOS (x86_64-linux)    | Personal workstation         | AMD GPU and desktop configuration                                                        |

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

## 📖 Documentation Index

We maintain comprehensive documentation for all parts of the fleet inside the [`docs/`](docs/) directory:

### Core Architecture Guides

- 🔐 **[Secrets Management Architecture](docs/secrets.md)**: SOPS age configuration, host boundary boundaries, and Nix
  store leak protection patterns.
- 🚀 **[Deployments & Pipelines](docs/deployments.md)**: `deploy-rs` definitions, remote build pipelines, and SSH
  multiplexing.
- 📐 **[Fleet Standards & Trends](docs/standards.md)**: NFS loopbacks, wait-for-host guards, PgBouncer setups, and
  Tailscale optimizations.
- ⚙️ **[Custom NixOS Options](docs/custom-options.md)**: Details on the custom `services.build-cache` and
  `fleet.waitForHost` options.
- 📊 **[Distributed Performance Monitoring](docs/monitoring.md)**: How the round-robin `iperf3-speedtest-coordinator`
  daemon collects performance metrics.
- 💾 **[Disk Partitioning & Bootstrap](docs/storage-disko.md)**: Declarative storage configuration using Disko and
  bootstrapping instructions.

### Host Profiles

Individual host profiles detailing workstation setups and local integrations:

- 🎮 **[gaming Workstation](docs/hosts/gaming.md)**: GPU drivers, Vulkan configurations, ratbagd, keyd, and Plasma 6
  settings.
- 🍓 **[rpi4 Backup/Failover Node](docs/hosts/rpi4.md)**: USB external backup storage, systemd logs rotation, and
  failover replicas.
- 🗃️ **[xcloud-postgres Database Node](docs/hosts/xcloud-postgres.md)**: Isolated database volume configurations using
  Disko.

### Service Configurations Index

Detailed profiles explaining configuration choices, ports, storage dependencies, and keys:

| Observability & Network                                           | Apps & Databases                                  | Storage & CI/CD                                              | Media & Gaming                                   |
|:------------------------------------------------------------------|:--------------------------------------------------|:-------------------------------------------------------------|:-------------------------------------------------|
| 🔍 [Prometheus](docs/services/prometheus.md)                      | 💾 [PostgreSQL](docs/services/postgres.md)        | 📦 [Container Registry](docs/services/container-registry.md) | 🎬 [Jellyfin](docs/services/jellyfin.md)         |
| 📊 [Grafana](docs/services/grafana.md)                            | 🔑 [Keycloak](docs/services/keycloak.md)          | 🤖 [GitLab Runner](docs/services/gitlab-runner.md)           | 📸 [Immich](docs/services/immich.md)             |
| 🪵 [Loki](docs/services/loki.md)                                  | 🦊 [GitLab](docs/services/gitlab.md)              | 💾 [Garage S3](docs/services/garage.md)                      | 🕹️ [Luanti (Minetest)](docs/services/luanti.md) |
| 📈 [Mimir](docs/services/mimir.md)                                | 🔒 [Vaultwarden](docs/services/vaultwarden.md)    |                                                              |                                                  |
| 🖧 [Tailscale](docs/services/tailscale.md)                        | 🗃️ [Paperless-ngx](docs/services/paperless.md)   |                                                              |                                                  |
| 🌐 [oauth2-proxy](docs/services/oauth2-proxy.md)                  | 📋 [Vikunja](docs/services/vikunja.md)            |                                                              |                                                  |
| 🔔 [ntfy](docs/services/ntfy.md)                                  | 💰 [Actual Budget](docs/services/actualbudget.md) |                                                              |                                                  |
| 📡 [Blackbox Exporter](docs/services/blackbox-exporter.md)        | 💻 [Coder Server](docs/services/coder.md)         |                                                              |                                                  |
| ⚡ [Tailscale Exporter](docs/services/tailscale-exporter.md)       |                                                   |                                                              |                                                  |
| 🔌 [TrueNAS Exporter](docs/services/truenas-graphite-exporter.md) |                                                   |                                                              |                                                  |
| 📝 [Caddy Proxy](docs/services/caddy.md)                          |                                                   |                                                              |                                                  |

---

## 🚀 Getting Started & Deployments

System deployments are fully automated using `deploy-rs`.

### Local Execution (via Makefile)

Common commands are mapped inside the [Makefile](Makefile):

```bash
# Verify formatting and flake evaluations
make lint

# Deploy the entire fleet
make deploy

# Deploy cloud gateways only
make deploy-cloud

# Deploy Proxmox hypervisor virtual machines
make deploy-proxmox

# Reboot all hosts in sequence
make reboot-all
```

### Automated Deployments

Every merge to the `main` branch triggers the GitLab CI runner to compile node closures, execute remote builds, copy
assets, and activate the configurations concurrently across your nodes.
