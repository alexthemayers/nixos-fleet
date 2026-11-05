#!/usr/bin/env python3
"""Render Prometheus, Alertmanager, and Graphite config from the NixOS modules."""

import json
import subprocess
import sys
from pathlib import Path


def dump_yaml(value, indent=0):
    return "\n".join(_yaml_lines(value, indent)) + "\n"


def _yaml_lines(value, indent):
    pad = "  " * indent
    if isinstance(value, dict):
        lines = []
        for key, item in value.items():
            if isinstance(item, (dict, list)):
                lines.append(f"{pad}{key}:")
                lines.extend(_yaml_lines(item, indent + 1))
            else:
                lines.append(f"{pad}{key}: {_yaml_scalar(item)}")
        return lines
    if isinstance(value, list):
        lines = []
        for item in value:
            if isinstance(item, dict):
                first = True
                for key, child in item.items():
                    marker = "- " if first else "  "
                    first = False
                    if isinstance(child, (dict, list)):
                        lines.append(f"{pad}{marker}{key}:")
                        lines.extend(_yaml_lines(child, indent + 2))
                    else:
                        lines.append(f"{pad}{marker}{key}: {_yaml_scalar(child)}")
            elif isinstance(item, list):
                lines.append(f"{pad}-")
                lines.extend(_yaml_lines(item, indent + 1))
            else:
                lines.append(f"{pad}- {_yaml_scalar(item)}")
        return lines
    return [f"{pad}{_yaml_scalar(value)}"]


def _yaml_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value)
    if value is None:
        return "null"
    return json.dumps(str(value))


def strip(value):
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            if item is None:
                continue
            cleaned = strip(item)
            if cleaned is None or cleaned == {} or cleaned == []:
                continue
            out[key] = cleaned
        return out
    if isinstance(value, list):
        cleaned_items = []
        for item in value:
            if item is None:
                continue
            cleaned = strip(item)
            if cleaned is None or cleaned == {} or cleaned == []:
                continue
            cleaned_items.append(cleaned)
        return cleaned_items
    return value


def nix_json(repo: Path, attr: str):
    raw = subprocess.check_output(
        ["nix", "eval", "--json", attr],
        cwd=repo,
        text=True,
    )
    return json.loads(raw)


def main() -> None:
    repo = Path(sys.argv[1]).resolve()
    dest = Path(sys.argv[2]).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    host = "proxmox-observability"

    global_config = strip(
        nix_json(repo, f"{host_attr(host)}.services.prometheus.globalConfig")
    )
    scrapes = strip(
        nix_json(repo, f"{host_attr(host)}.services.prometheus.scrapeConfigs")
    )
    alertmanager = strip(
        nix_json(
            repo,
            f"{host_attr(host)}.services.prometheus.alertmanager.configuration",
        )
    )
    graphite = strip(
        nix_json(
            repo,
            f"{host_attr(host)}.services.prometheus.exporters.graphite.mappingSettings",
        )
    )

    prometheus = {
        "global": global_config,
        "rule_files": ["/etc/prometheus/rules.yaml"],
        "alerting": {
            "alertmanagers": [
                {"static_configs": [{"targets": ["127.0.0.1:9093"]}]}
            ]
        },
        "scrape_configs": scrapes,
    }
    (dest / "prometheus.yml").write_text(dump_yaml(prometheus))
    (dest / "alertmanager.yml").write_text(dump_yaml(alertmanager))
    (dest / "graphite-mapping.yml").write_text(dump_yaml(graphite))

    rules_json = subprocess.check_output(
        [
            "nix",
            "eval",
            "--raw",
            f'{host_attr(host)}.environment.etc."observability/live-alert-rules.json".text',
        ],
        cwd=repo,
        text=True,
    )
    rules = strip(json.loads(rules_json))
    (dest / "rules.yaml").write_text(dump_yaml(rules))


def host_attr(host: str) -> str:
    return f".#nixosConfigurations.{host}.config"


if __name__ == "__main__":
    main()
