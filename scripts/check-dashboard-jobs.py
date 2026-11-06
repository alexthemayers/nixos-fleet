#!/usr/bin/env python3
"""Fail when Grafana dashboard PromQL references unknown scrape job names.

Walks committed dashboard JSON under the observability role and extracts
job="..." / job=~"..." literals. Variables ($job) are skipped. Each literal
must appear as a scrape_configs.job_name in prometheus.yml.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("check-dashboard-jobs.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
PROM = (
    ROOT
    / "collections/ansible_collections/fleet/debian_guest/roles/observability/files/prometheus.yml"
)
DASH_ROOT = (
    ROOT
    / "collections/ansible_collections/fleet/debian_guest/roles/observability/files/dashboards"
)

JOB_RE = re.compile(r'job\s*(=|=~)\s*"([^"]+)"')


def scrape_jobs(path: Path) -> set[str]:
    data = yaml.safe_load(path.read_text())
    return {j["job_name"] for j in (data.get("scrape_configs") or []) if j.get("job_name")}


def walk_exprs(node: object, out: list[str]) -> None:
    if isinstance(node, dict):
        expr = node.get("expr")
        if isinstance(expr, str):
            out.append(expr)
        for v in node.values():
            walk_exprs(v, out)
    elif isinstance(node, list):
        for item in node:
            walk_exprs(item, out)


def job_literals(expr: str) -> list[str]:
    found: list[str] = []
    for op, val in JOB_RE.findall(expr):
        if "$" in val:
            continue
        parts = re.split(r"\|", val) if op == "=~" else [val]
        for part in parts:
            part = part.strip()
            if not part or part in (".*", ".+"):
                continue
            found.append(part)
    return found


def main() -> int:
    if not PROM.is_file():
        sys.stderr.write(f"missing {PROM}\n")
        return 1
    if not DASH_ROOT.is_dir():
        sys.stderr.write(f"missing {DASH_ROOT}\n")
        return 1

    jobs = scrape_jobs(PROM)
    unknown: dict[str, set[str]] = {}
    files = 0
    exprs = 0

    for path in sorted(DASH_ROOT.rglob("*.json")):
        files += 1
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            sys.stderr.write(f"{path}: invalid JSON: {e}\n")
            return 1
        found: list[str] = []
        walk_exprs(data, found)
        exprs += len(found)
        rel = str(path.relative_to(DASH_ROOT))
        for expr in found:
            for lit in job_literals(expr):
                if lit not in jobs:
                    unknown.setdefault(lit, set()).add(rel)

    if unknown:
        sys.stderr.write(
            "Dashboard PromQL references scrape jobs that are not in "
            f"{PROM.relative_to(ROOT)}:\n"
        )
        for lit in sorted(unknown):
            where = ", ".join(sorted(unknown[lit]))
            sys.stderr.write(f"  job={lit!r} in {where}\n")
        return 1

    print(
        f"✓ Dashboard job names match scrapes "
        f"({files} dashboards, {exprs} exprs, {len(jobs)} scrape jobs)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
