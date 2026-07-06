# Codebase Deviations TODO List

This document tracks known deviations from the established standards within the `nixos-fleet` codebase. Fixing these
deviations will align all services with the core architectural patterns.

## 1. Storage Availability Guards (`fleet.waitForHost`)

**Standard**: All remote NFS mounts should use the centralized `fleet.waitForHost` option to generate their
`wait-for-host-<name>` dependency guards.

**Deviations**:

- `[ ]` **Actualbudget** (`services/actualbudget.nix`): Manually defines `actual-wait-for-nas` systemd oneshot ping loop
  instead of utilizing the `fleet.waitForHost` module.
- `[ ]` **Jellyfin** (`services/jellyfin.nix`): Manually defines `jellyfin-wait-for-nas` systemd oneshot ping loop
  instead of utilizing the `fleet.waitForHost` module.

**Action**: Refactor these services to utilize `fleet.waitForHost.<name>.host = "truenas-scale";` and update the
`fileSystems` mount options to depend on the auto-generated service instead of the manually defined ones.

## 2. Secrets Security (Strict Nix Store Leak Prevention)

**Standard**: No plain-text secrets should be defined in `.nix` files, as this compiles them directly into the
world-readable `/nix/store`.

**Deviations**:

- `[ ]` **Keycloak** (`services/keycloak.nix`): The `initialAdminPassword = "admin"` option is defined as a plain-text
  string, violating the secret protection standards.

**Action**: Refactor the Keycloak configuration to source the initial admin password from a SOPS-encrypted secret file,
potentially via `sops.templates` or via an environment file injection if the module supports it.
