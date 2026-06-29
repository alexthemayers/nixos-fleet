# NixOS Fleet

Welcome to `nixos-fleet`, the declarative infrastructure repository managing a unified cluster of NixOS nodes, personal
workstations, cloud gateways, and home lab virtual machines.

This repository uses **Nix Flakes** to describe host architectures, **SOPS** for encrypted secret injection, **deploy-rs
** for system activation, and a **GitLab CI** pipeline for continuous integration and automated deployment.

---

## 🗺️ Fleet Overview

The fleet is comprised of the following nodes (defined under [`hosts/`](file:///Users/alex/code/nixos-fleet/hosts/)):

| Host Name                   | Operating System / Arch | Description / Role           | Main Services                                                                            |
|:----------------------------|:------------------------|:-----------------------------|:-----------------------------------------------------------------------------------------|
| **`proxmox-gitlab`**        | NixOS (x86_64-linux)    | Core application host        | GitLab, Keycloak, Vaultwarden, Vikunja, Actual Budget, Paperless-ngx, Container Registry |
| **`proxmox-observability`** | NixOS (x86_64-linux)    | Central metrics & logging    | Grafana, Prometheus, Loki, Mimir, ntfy                                                   |
| **`proxmox-gaming`**        | NixOS (x86_64-linux)    | Compilation and game hosting | Coder Server, GitLab Runner (Podman), Luanti (Minetest)                                  |
| **`proxmox-db`**            | NixOS (x86_64-linux)    | S3 Object storage gateway    | Garage S3 daemon                                                                         |
| **`proxmox-video`**         | NixOS (x86_64-linux)    | Home entertainment center    | Jellyfin (QSV Transcoding), Immich (Intel ML acceleration)                               |
| **`xcloud-caddy`**          | NixOS (x86_64-linux)    | Public facing cloud ingress  | Caddy reverse proxy, OAuth2 Proxy, Redis session store                                   |
| **`xcloud-postgres`**       | NixOS (x86_64-linux)    | Core fleet database          | PostgreSQL 17, PgBouncer                                                                 |
| **`rpi4`**                  | NixOS (aarch64-linux)   | Failover and local backup    | Failover replicas (Keycloak, Vaultwarden, Grafana, Loki, Mimir), Blackbox Exporter       |
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

For details, see the **[Codebase Standards Document](file:///Users/alex/code/nixos-fleet/docs/standards.md)**.

---

## 📖 Documentation Index

We maintain comprehensive documentation for all parts of the fleet inside the [
`docs/`](file:///Users/alex/code/nixos-fleet/docs/) directory:

### Core Architecture Guides

- 🔐 **[Secrets Management Architecture](file:///Users/alex/code/nixos-fleet/docs/secrets.md)**: SOPS age configuration,
  host boundary boundaries, and Nix store leak protection patterns.
- 🚀 **[Deployments & Pipelines](file:///Users/alex/code/nixos-fleet/docs/deployments.md)**: `deploy-rs` definitions,
  remote build pipelines, and SSH multiplexing.
- 📐 **[Fleet Standards & Trends](file:///Users/alex/code/nixos-fleet/docs/standards.md)**: NFS loopbacks, wait-for-host
  guards, PgBouncer setups, and Tailscale optimizations.

### Service Configurations Index

Detailed profiles explaining configuration choices, ports, storage dependencies, and keys:

| Observability & Network                                                                               | Apps & Databases                                                                      | Storage & CI/CD                                                                                  | Media & Gaming                                                                       |
|:------------------------------------------------------------------------------------------------------|:--------------------------------------------------------------------------------------|:-------------------------------------------------------------------------------------------------|:-------------------------------------------------------------------------------------|
| 🔍 [Prometheus](file:///Users/alex/code/nixos-fleet/docs/services/prometheus.md)                      | 💾 [PostgreSQL](file:///Users/alex/code/nixos-fleet/docs/services/postgres.md)        | 📦 [Container Registry](file:///Users/alex/code/nixos-fleet/docs/services/container-registry.md) | 🎬 [Jellyfin](file:///Users/alex/code/nixos-fleet/docs/services/jellyfin.md)         |
| 📊 [Grafana](file:///Users/alex/code/nixos-fleet/docs/services/grafana.md)                            | 🔑 [Keycloak](file:///Users/alex/code/nixos-fleet/docs/services/keycloak.md)          | 🤖 [GitLab Runner](file:///Users/alex/code/nixos-fleet/docs/services/gitlab-runner.md)           | 📸 [Immich](file:///Users/alex/code/nixos-fleet/docs/services/immich.md)             |
| 🪵 [Loki](file:///Users/alex/code/nixos-fleet/docs/services/loki.md)                                  | 🦊 [GitLab](file:///Users/alex/code/nixos-fleet/docs/services/gitlab.md)              | 💾 [Garage S3](file:///Users/alex/code/nixos-fleet/docs/services/garage.md)                      | 🕹️ [Luanti (Minetest)](file:///Users/alex/code/nixos-fleet/docs/services/luanti.md) |
| 📈 [Mimir](file:///Users/alex/code/nixos-fleet/docs/services/mimir.md)                                | 🔒 [Vaultwarden](file:///Users/alex/code/nixos-fleet/docs/services/vaultwarden.md)    |                                                                                                  |                                                                                      |
| 🖧 [Tailscale](file:///Users/alex/code/nixos-fleet/docs/services/tailscale.md)                        | 🗃️ [Paperless-ngx](file:///Users/alex/code/nixos-fleet/docs/services/paperless.md)   |                                                                                                  |                                                                                      |
| 🌐 [oauth2-proxy](file:///Users/alex/code/nixos-fleet/docs/services/oauth2-proxy.md)                  | 📋 [Vikunja](file:///Users/alex/code/nixos-fleet/docs/services/vikunja.md)            |                                                                                                  |                                                                                      |
| 🔔 [ntfy](file:///Users/alex/code/nixos-fleet/docs/services/ntfy.md)                                  | 💰 [Actual Budget](file:///Users/alex/code/nixos-fleet/docs/services/actualbudget.md) |                                                                                                  |                                                                                      |
| 📡 [Blackbox Exporter](file:///Users/alex/code/nixos-fleet/docs/services/blackbox-exporter.md)        | 💻 [Coder Server](file:///Users/alex/code/nixos-fleet/docs/services/coder.md)         |                                                                                                  |                                                                                      |
| ⚡ [Tailscale Exporter](file:///Users/alex/code/nixos-fleet/docs/services/tailscale-exporter.md)       |                                                                                       |                                                                                                  |                                                                                      |
| 🔌 [TrueNAS Exporter](file:///Users/alex/code/nixos-fleet/docs/services/truenas-graphite-exporter.md) |                                                                                       |                                                                                                  |                                                                                      |
| 📝 [Caddy Proxy](file:///Users/alex/code/nixos-fleet/docs/services/caddy.md)                          |                                                                                       |                                                                                                  |                                                                                      |

---

## 🚀 Getting Started & Deployments

System deployments are fully automated using `deploy-rs`.

### Local Execution (via Makefile)

Common commands are mapped inside the [Makefile](file:///Users/alex/code/nixos-fleet/Makefile):

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
