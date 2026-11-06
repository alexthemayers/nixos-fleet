#!/usr/bin/env python3
"""Fail when required secret key paths are missing from encrypted sops files.

Does not decrypt. SOPS leaves key names in plaintext; values stay ciphertext.
Covers NixOS hosts (keys declared in sops.secrets) and Ansible Debian guests
(keys referenced by fleet.debian_guest roles). Wire into CI.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("check-secrets-keys.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]

# Keys each Ansible guest playbook reads from debian_guest_secrets.
# Keep in sync with roles under collections/.../debian_guest/roles/.
ANSIBLE_REQUIRED: dict[str, frozenset[str]] = {
    "proxmox-applications-debian": frozenset(
        {
            "actualbudget/client_secret",
            "immich/env",
            "jellyfin/sso_oid_secret",
            "keycloak/bootstrap_admin_password",
            "paperless/client_secret",
            "postgres/keycloak_password",
            "postgres/paperless_password",
            "postgres/vikunja_password",
            "redis/paperless_password",
            "redis/vikunja_password",
            "tailscale/auth_key",
            "vaultwarden/env",
            "vikunja/client_secret",
            "vikunja/jwt_secret",
        }
    ),
    "proxmox-gitlab-debian": frozenset(
        {
            "gitlab/active_record/deterministic",
            "gitlab/active_record/primary",
            "gitlab/active_record/salt",
            "gitlab/client_secret",
            "gitlab/db_encryption_secret",
            "gitlab/jws",
            "gitlab/otp",
            "gitlab/registry_cert",
            "gitlab/registry_key",
            "gitlab/secret",
            "postgres/gitlab_password",
            "ssh_backup/privkey",
            "tailscale/auth_key",
        }
    ),
    "proxmox-observability-debian": frozenset(
        {
            "grafana/admin_password",
            "grafana/oauth_secret",
            "grafana/secret_key",
            "ntfy/alertmanager_password",
            "oauth2-proxy/blackbox_token",
            "postgres/grafana_password",
            "tailscale/auth_key",
            "tailscale/exporter_env",
        }
    ),
    # Builder still decrypts for Tailscale join; other keys are legacy.
    "proxmox-dev": frozenset(
        {
            "tailscale/auth_key",
        }
    ),
}

# Inventory hostname → secrets/<dir>/secrets.yaml
ANSIBLE_SECRET_DIRS: dict[str, str] = {
    "proxmox-applications-debian": "proxmox-applications-debian",
    "proxmox-gitlab-debian": "proxmox-gitlab-debian",
    "proxmox-observability-debian": "proxmox-observability-debian",
    "proxmox-dev": "proxmox-dev",
}


def walk_keys(node: object, prefix: str = "") -> list[str]:
    if isinstance(node, dict):
        out: list[str] = []
        for k, v in node.items():
            if k == "sops":
                continue
            out.extend(walk_keys(v, f"{prefix}{k}/"))
        return out
    return [prefix.rstrip("/")]


def stored_keys(path: Path) -> set[str]:
    data = yaml.safe_load(path.read_text())
    if not isinstance(data, dict):
        return set()
    return set(walk_keys(data))


def nixos_declared(host: str) -> set[str]:
    proc = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f".#nixosConfigurations.{host}.config.sops.secrets",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(
            f"{host}: nix eval sops.secrets failed:\n{proc.stderr}\n"
        )
        return set()
    return set(json.loads(proc.stdout).keys())


def nixos_hosts() -> list[str]:
    proc = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            ".#nixosConfigurations",
            "--apply",
            "builtins.attrNames",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return sorted(json.loads(proc.stdout))


def main() -> int:
    status = 0

    for host in nixos_hosts():
        path = ROOT / "secrets" / host / "secrets.yaml"
        if not path.is_file():
            sys.stderr.write(f"{host}: missing {path.relative_to(ROOT)}\n")
            status = 1
            continue
        declared = nixos_declared(host)
        if not declared:
            # Host with no sops.secrets is fine if the file exists for other use.
            print(f"{host}: no sops.secrets declared")
            continue
        stored = stored_keys(path)
        missing = sorted(declared - stored)
        if missing:
            status = 1
            sys.stderr.write(
                f"{host}: MISSING (declared in Nix, absent from "
                f"{path.relative_to(ROOT)}):\n"
            )
            for k in missing:
                sys.stderr.write(f"    {k}\n")
        else:
            print(f"{host}: {len(declared)} Nix secret keys ok")

    for guest, dirname in sorted(ANSIBLE_SECRET_DIRS.items()):
        path = ROOT / "secrets" / dirname / "secrets.yaml"
        required = ANSIBLE_REQUIRED[guest]
        if not path.is_file():
            sys.stderr.write(f"{guest}: missing {path.relative_to(ROOT)}\n")
            status = 1
            continue
        stored = stored_keys(path)
        missing = sorted(required - stored)
        if missing:
            status = 1
            sys.stderr.write(
                f"{guest}: MISSING (Ansible requires, absent from "
                f"{path.relative_to(ROOT)}):\n"
            )
            for k in missing:
                sys.stderr.write(f"    {k}\n")
        else:
            print(f"{guest}: {len(required)} Ansible secret keys ok")

    return status


if __name__ == "__main__":
    raise SystemExit(main())
