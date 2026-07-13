# GitLab Service Configuration

This document describes the deployment and configuration details of the **GitLab** service in the `nixos-fleet`
infrastructure.

## Overview

GitLab is the primary Git repository hosting, code review, and CI/CD orchestration platform. It is deployed on the
general applications node, **`proxmox-applications-2`**.

## Networking and Ports

- **Internal Port**: `8080` (HTTP, exposed on localhost/Tailscale network).
- **Public Domain**: `https://gitlab.alexmayers.co.za` (reverse proxied via Caddy).
- **Proxy Protocol**: Nginx reverse-proxies the GitLab workhorse socket internally.
- **Git SSH**: Port `22` on the host handles GitLab SSH clone traffic.

## Secrets Management

GitLab requires extensive secrets decrypted by SOPS under ownership `gitlab:gitlab` (mode `0440`):

- `postgres/gitlab_password`: Password for the external database connection.
- `gitlab/client_secret`: Keycloak SSO integration client secret.
- `gitlab/root_password`: Seed administrator password.
- Encryption Keys: `gitlab/secret`, `gitlab/db_encryption_secret`, `gitlab/otp`, `gitlab/jws`, and ActiveRecord keys (
  `primary`, `deterministic`, `salt`).
- Container Registry Keys: `gitlab/registry_key` (mode `0400`) and `gitlab/registry_cert` (mode `0444`) to sign/verify
  authentication tokens between GitLab and the Docker Registry.
- `ssh_backup/privkey`: Private key for synchronizing backup archives.

## Database Integration

GitLab is integrated with the central PostgreSQL database instance:

- **Host**: `xcloud-postgres`
- **Database/User**: `gitlab`
- **Port**: `5432` (PgBouncer)
- **Settings**: Database creation on the local host is disabled (`databaseCreateLocally = false`).

## Storage and Bind Mounts

- **Registry Storage**: The registry upload directory `/var/lib/gitlab/shared/registry` is bind-mounted directly to
  `/mnt/ssd/container-registry/gitlab` (located on the NFS loopback ext4 attachment `container-registry.img`) to
  maintain filesystem integrity and speed.
- **Nginx Caching**: Active caching is configured at `/var/cache/nginx/gitlab` with a maximum size of `1g` and stale
  cache fallback settings to improve asset load performance.

## Key Configurations

- **Keycloak SSO**: Users authenticate using generic OpenID Connect linked to Keycloak. Auto-signup is enabled but
  requires admin approval:
  ```nix
  omniauth = {
    enabled = true;
    allow_single_sign_on = [ "openid_connect" ];
    auto_sign_in_with_provider = "openid_connect";
  };
  ```
  The client secret is read dynamically from the sops-decrypted path at runtime using Ruby block evaluation to avoid
  store leaks:
  ```ruby
  secret = "<%= File.read('/run/secrets/gitlab/client_secret').strip %>"
  ```
- **Performance Tuning (Memory Footprint Reduction)**:
    - Puma is restricted to `2` workers and `1-4` threads.
    - Sidekiq concurrency is limited to `10`.
    - Ruby Garbage Collection is heavily optimized using `extraEnv` variables (e.g. `RUBY_GC_MALLOC_LIMIT = "67108864"`)
      to prevent memory leaks and bloating.
- **Backups & PostgreSQL 17 Workaround**:
    - The backup system runs daily at 03:00.
    - **PG Upgrade Hack**: Because the fleet runs PostgreSQL 17 but NixOS's default GitLab package depends on PostgreSQL
      16 utilities, standard backup runs would fail due to version mismatch in `pg_dump`. To solve this,
      `systemd.services.gitlab-backup` is configured with a read-only bind path shadowing the PostgreSQL 16 binaries
      with version 17 binaries:
      ```nix
      serviceConfig.BindReadOnlyPaths = [ "${pkgs.postgresql_17}/bin:${pkgs.postgresql_16}/bin" ];
      ```
    - **Sync**: After a successful backup runs, the `gitlab-backup-sync` service transfers the compressed `.zstd`
      archives to `alex@rpi4:/mnt/usb-backup/gitlab_backups/` using `rsync` over SSH.
