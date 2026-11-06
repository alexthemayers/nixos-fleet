#!/usr/bin/env python3
"""Render every Vector config in the fleet and prove they share one pipeline.

Vector runs on NixOS hosts (config/observability.nix), on the Debian guests
(fleet.debian_guest monitoring role) and on the Proxmox host (ansible/roles/
vector). The journal remap (VRL) and the Loki sink live once in config/vector/.
This check renders all three consumers and fails when one drifts from the
shared files, then runs `vector validate` on each render.

`vector` is in `.#ci-tools` on Linux. On Darwin set ALLOW_NO_VECTOR=1 to run
the drift checks without the validate step.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("check-vector-config.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "config" / "vector"
GUEST_TEMPLATE = (
    ROOT
    / "collections/ansible_collections/fleet/debian_guest/roles/monitoring"
    / "templates/vector.yaml.j2"
)
PVE_TEMPLATE = ROOT / "ansible/roles/vector/templates/vector.yaml.j2"
# (role defaults file, variable, directory of the playbook that runs the role)
CONFIG_DIR_DEFAULTS = (
    (
        ROOT / "ansible/roles/vector/defaults/main.yml",
        "vector_config_dir",
        ROOT / "ansible",
    ),
    (
        ROOT
        / "collections/ansible_collections/fleet/debian_guest/roles/monitoring/defaults/main.yml",
        "debian_guest_vector_config_dir",
        ROOT / "collections/ansible_collections/fleet/debian_guest/playbooks",
    ),
)
NIX_HOSTS = ("xcloud-postgres", "xcloud-caddy", "gaming")
ENDPOINT = "http://proxmox-observability-debian:3100"
# Per-consumer fields that are allowed to differ from loki-sink.json.
SINK_LOCAL_KEYS = ("inputs", "endpoint")


def nix_settings(host: str) -> dict:
    out = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f".#nixosConfigurations.{host}.config.services.vector.settings",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(out)


def render_template(template: Path, variables: dict) -> dict:
    env = dict(os.environ, LC_ALL="C.UTF-8", LANG="C.UTF-8", ANSIBLE_NOCOLOR="1")
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "vector.yaml"
        subprocess.run(
            [
                "ansible",
                "localhost",
                "-c",
                "local",
                "-i",
                "localhost,",
                "-m",
                "ansible.builtin.template",
                "-a",
                f"src={template} dest={dest}",
                "-e",
                json.dumps(variables),
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
        )
        return yaml.safe_load(dest.read_text())


def resolved_config_dir(defaults: Path, var: str, playbook_dir: Path) -> Path | None:
    """The role's default `*_config_dir` with `playbook_dir` filled in."""
    value = (yaml.safe_load(defaults.read_text()) or {}).get(var)
    if not isinstance(value, str) or "{{ playbook_dir }}" not in value:
        return None
    return Path(os.path.normpath(value.replace("{{ playbook_dir }}", str(playbook_dir))))


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def default_path_problems(
    entries: tuple[tuple[Path, str, Path], ...], shared: Path
) -> list[str]:
    problems = []
    for defaults, var, playbook_dir in entries:
        got = resolved_config_dir(defaults, var, playbook_dir)
        if got != Path(os.path.normpath(shared)):
            problems.append(
                f"{rel(defaults)}: {var} must be "
                f"`{{{{ playbook_dir }}}}/...` resolving to config/vector/ from "
                f"{rel(playbook_dir)}, got {got}"
            )
    return problems


def drift(name: str, cfg: dict, host: str, vrl: str, sink: dict) -> list[str]:
    problems: list[str] = []
    expected_vrl = vrl.replace("@host@", host)
    got = cfg.get("transforms", {}).get("journal_remap", {}).get("source")
    if got is None:
        problems.append(f"{name}: no transforms.journal_remap.source")
    elif got.strip() != expected_vrl.strip():
        problems.append(f"{name}: journal_remap.source differs from config/vector/journal-remap.vrl")

    loki = dict(cfg.get("sinks", {}).get("loki", {}))
    for key in SINK_LOCAL_KEYS:
        loki.pop(key, None)
    if loki != sink:
        problems.append(f"{name}: sinks.loki differs from config/vector/loki-sink.json")

    endpoint = cfg.get("sinks", {}).get("loki", {}).get("endpoint")
    if not endpoint or not str(endpoint).startswith("http"):
        problems.append(f"{name}: sinks.loki.endpoint missing")
    exporter = cfg.get("sinks", {}).get("prometheus_exporter", {})
    if exporter.get("address") != "0.0.0.0:9598":
        problems.append(f"{name}: prometheus_exporter must listen on 0.0.0.0:9598")
    if "journald" not in cfg.get("sources", {}):
        problems.append(f"{name}: no journald source")
    return problems


def validate(name: str, cfg: dict, vector: str) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "vector.json"
        path.write_text(json.dumps(cfg))
        proc = subprocess.run(
            [vector, "validate", "--no-environment", str(path)],
            capture_output=True,
            text=True,
        )
    if proc.returncode != 0:
        return [f"{name}: vector validate failed:\n{proc.stdout}{proc.stderr}"]
    return []


def main() -> int:
    vrl = (SHARED / "journal-remap.vrl").read_text()
    sink = json.loads((SHARED / "loki-sink.json").read_text())
    if "@host@" not in vrl:
        sys.stderr.write("journal-remap.vrl lost its @host@ placeholder\n")
        return 1

    configs: dict[str, tuple[dict, str]] = {}
    for host in NIX_HOSTS:
        configs[f"nix:{host}"] = (nix_settings(host), host)
    configs["ansible:debian-guest"] = (
        render_template(
            GUEST_TEMPLATE,
            {
                "debian_guest_vector_config_dir": str(SHARED),
                "debian_guest_tailscale_hostname": "proxmox-guest-test",
                "debian_guest_loki_endpoint": ENDPOINT,
            },
        ),
        "proxmox-guest-test",
    )
    configs["ansible:proxmox-host"] = (
        render_template(
            PVE_TEMPLATE,
            {
                "vector_config_dir": str(SHARED),
                "vector_host_name": "proxmox",
                "vector_loki_endpoint": ENDPOINT,
            },
        ),
        "proxmox",
    )

    problems: list[str] = default_path_problems(CONFIG_DIR_DEFAULTS, SHARED)
    for name, (cfg, host) in configs.items():
        problems += drift(name, cfg, host, vrl, sink)

    vector = shutil.which("vector")
    if vector is None:
        if os.environ.get("ALLOW_NO_VECTOR") == "1":
            sys.stderr.write("warning: vector not on PATH; skipped `vector validate`\n")
        else:
            problems.append("vector not on PATH (.#ci-tools); set ALLOW_NO_VECTOR=1 on Darwin")
    else:
        for name, (cfg, _) in configs.items():
            problems += validate(name, cfg, vector)

    if problems:
        sys.stderr.write("\n".join(problems) + "\n")
        return 1
    print(f"✓ Vector configs share config/vector/ ({len(configs)} consumers)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
