# Secrets Management

This document describes how secrets are configured, encrypted, and managed in the `nixos-fleet` infrastructure.

## SOPS (Secrets OPeration Suite)

All sensitive data in this repository (database passwords, API tokens, private keys) are encrypted at rest using [SOPS](https://github.com/getsops/sops) and stored directly in Git. Encryption and decryption are managed using a hybrid setup of PGP/SSH keys and the modern **age** encryption tool.

### Encryption Configuration (`.sops.yaml`)

The SOPS configuration is stored in [.sops.yaml](../.sops.yaml). It defines:
1. **Public Keys**:
   - `alex`: The administrator's SSH public key used for local administration/decryption.
   - Host keys: Individual public `age` keys generated on each target host.
2. **Creation Rules**:
   - Secrets are partitioned host-by-host under `secrets/<hostname>/`.
   - Each host's secrets directory is mapped only to the administrator (`alex`) and the specific host's `age` public key.
   - This architecture limits the blast radius: if a host key is compromised, only that specific host's secrets can be decrypted.

```yaml
# Examples of mapping in .sops.yaml:
creation_rules:
  - path_regex: secrets/xcloud-postgres/.*\.yaml$
    key_groups:
      - age:
          - *alex
          - *xcloud_postgres
```

## Host NixOS Decryption Integration (`config/secrets.nix`)

In the NixOS configuration, [sops-nix](https://github.com/Mic92/sops-nix) is integrated via [config/secrets.nix](../config/secrets.nix).

It dynamically loads the host-specific secrets file by parsing the hostname:
```nix
sops.defaultSopsFile = ./../secrets + "/${config.networking.hostName}/secrets.yaml";
sops.defaultSopsFormat = "yaml";
```

### Decryption Key Placement
At host provisioning time, the host's private `age` key must be placed at `/var/lib/sops-nix/key.txt` (or the host's SSH host key must be accessible) to allow the system to automatically decrypt `secrets.yaml` into runtime secrets paths at boot.

## Safe Runtime Secret Injection (Nix Store Leak Prevention)

A major challenge in NixOS configuration is that the Nix store is world-readable. If secrets are written directly to Nix attributes (like environment variables in Nix configurations), they will compile into files in `/nix/store/` where any unprivileged user on the host can read them.

This repository enforces **Strict Nix Store Leak Prevention** using three patterns:

1. **Systemd `EnvironmentFile` (via `sops.templates`)**:
   - Secrets are mapped to SOPS placeholders.
   - A template is generated, which is rendered dynamically at boot time under a protected directory (e.g. `/run/secrets/`).
   - The service loads this template as an environment file.
   - Example:
     ```nix
     sops.templates."coder-env" = {
       owner = "coder";
       content = ''
         CODER_PG_CONNECTION_URL="postgres://coder:${config.sops.placeholder."postgres/coder_password"}@xcloud-postgres:5432/coder"
       '';
     };
     systemd.services.coder.serviceConfig.EnvironmentFile = [ config.sops.templates."coder-env".path ];
     ```

2. **Native Config File Loading (`$__file{}`)**:
   - Certain applications (e.g., Grafana) support referencing paths instead of raw strings for passwords.
   - The configuration references the decrypted sops file path directly:
     ```nix
     database.url = "postgres://grafana:$__file{${config.sops.secrets."postgres/grafana_password".path}}@xcloud-postgres:5432/grafana";
     ```

3. **Dynamic Template Evaluation (GitLab Omniauth)**:
   - For configs compiled as static files, inline shell or Ruby tags are used to read the secrets from files at daemon run time:
     ```nix
     secret = "<%= File.read('${config.sops.secrets."gitlab/client_secret".path}').strip %>";
     ```
