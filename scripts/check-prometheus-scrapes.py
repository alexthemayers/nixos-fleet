#!/usr/bin/env python3
"""Fail when Prometheus scrape targets drift from fleet.inventory.hosts.

Replaces the Nix assertions that used to run against
config.services.prometheus.scrapeConfigs on the deleted
proxmox-observability host. Reads the committed prometheus.yml and a
JSON list of inventory hosts (from nix eval).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import urlparse

try:
    import yaml
except ImportError:
    sys.stderr.write("check-prometheus-scrapes.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

URL_PROBE_JOBS = frozenset({"blackbox_http", "blackbox_http_internal"})


def host_of(target: str) -> str:
    if "://" in target:
        return urlparse(target).hostname or target
    return target.split(":", 1)[0]


def is_scrape_host_target(target: str) -> bool:
    # Blackbox URL probe jobs carry full URLs; those are not fleet hosts.
    return "://" not in target


def has_host_relabel(job: dict) -> bool:
    for relabel in job.get("relabel_configs") or []:
        if relabel.get("target_label") == "host":
            return True
    return False


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(
            f"usage: {sys.argv[0]} <prometheus.yml> <hosts.json>\n"
        )
        return 2

    prom_path = Path(sys.argv[1])
    hosts_path = Path(sys.argv[2])
    hosts = set(json.loads(hosts_path.read_text()))
    data = yaml.safe_load(prom_path.read_text())
    jobs = data.get("scrape_configs") or []

    unknown: list[str] = []
    missing_host_relabel: list[str] = []

    for job in jobs:
        name = job.get("job_name") or "<unnamed>"
        if name not in URL_PROBE_JOBS and not has_host_relabel(job):
            missing_host_relabel.append(name)

        for sc in job.get("static_configs") or []:
            for target in sc.get("targets") or []:
                if not is_scrape_host_target(target):
                    continue
                h = host_of(target)
                if h in ("localhost", "127.0.0.1"):
                    continue
                if h not in hosts:
                    unknown.append(f"{name}:{target}")

    unknown = sorted(set(unknown))
    missing_host_relabel = sorted(set(missing_host_relabel))
    failed = False

    # Empty scrape_configs is a silent production hole; CI must fail.
    if not jobs:
        failed = True
        sys.stderr.write(
            "prometheus.yml has zero scrape_configs; refusing empty config\n"
        )

    if unknown:
        failed = True
        sys.stderr.write(
            "Prometheus scrape targets reference hosts that are not in "
            "fleet.inventory.hosts:\n"
        )
        for t in unknown:
            sys.stderr.write(f"  {t}\n")

    if missing_host_relabel:
        failed = True
        sys.stderr.write(
            "Prometheus scrape jobs must set a host label from hostname:port "
            "(blackbox URL probes are exempt). Missing relabel_configs host:\n"
        )
        for name in missing_host_relabel:
            sys.stderr.write(f"  {name}\n")

    if failed:
        return 1

    print(
        f"✓ Prometheus scrapes match inventory "
        f"({len(jobs)} jobs, {len(hosts)} hosts)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
