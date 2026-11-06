#!/usr/bin/env python3
"""Fail when dashboard/rules PromQL references unknown scrape jobs or hosts.

Walks committed dashboard JSON and rules.yaml. Extracts job= / job=~ and
host= / host=~ literals. Variables ($job, $host) are skipped. Each job
literal must appear as a scrape_configs.job_name. Each host literal (or
regex) must match at least one name in fleet.inventory.hosts — a regex
that matches nothing is a vacuous pass and fails.
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
OBS = (
    ROOT
    / "collections/ansible_collections/fleet/debian_guest/roles/observability/files"
)
PROM = OBS / "prometheus.yml"
DASH_ROOT = OBS / "dashboards"
RULES = OBS / "rules.yaml"

# Word-ish boundary so exported_host= and similar do not match host=.
JOB_RE = re.compile(r'(?<![A-Za-z0-9_])job\s*(=|=~)\s*"([^"]+)"')
HOST_RE = re.compile(r'(?<![A-Za-z0-9_])host\s*(=|=~)\s*"([^"]+)"')


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


def matcher_literals(expr: str, pattern: re.Pattern[str]) -> list[tuple[str, str]]:
    """Return (op, literal) pairs. =~ values may be split on |."""
    found: list[tuple[str, str]] = []
    for op, val in pattern.findall(expr):
        if "$" in val:
            continue
        parts = re.split(r"\|", val) if op == "=~" else [val]
        for part in parts:
            part = part.strip()
            if not part or part in (".*", ".+"):
                continue
            found.append((op, part))
    return found


def job_literals(expr: str) -> list[str]:
    return [lit for _, lit in matcher_literals(expr, JOB_RE)]


def host_matches_inventory(op: str, lit: str, hosts: set[str]) -> bool:
    if op == "=":
        return lit in hosts
    try:
        rx = re.compile(lit)
    except re.error:
        return False
    return any(rx.search(h) for h in hosts)


def load_hosts(path: Path) -> set[str]:
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON list of host names")
    return {str(h) for h in data}


def collect_exprs() -> list[tuple[str, str]]:
    """Return (source_label, expr) pairs from dashboards and rules."""
    out: list[tuple[str, str]] = []
    for path in sorted(DASH_ROOT.rglob("*.json")):
        data = json.loads(path.read_text())
        found: list[str] = []
        walk_exprs(data, found)
        rel = str(path.relative_to(DASH_ROOT))
        for expr in found:
            out.append((rel, expr))
    if RULES.is_file():
        rules = yaml.safe_load(RULES.read_text()) or {}
        found: list[str] = []
        walk_exprs(rules, found)
        for expr in found:
            out.append(("rules.yaml", expr))
    return out


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 1:
        sys.stderr.write(f"usage: {sys.argv[0]} <hosts.json>\n")
        return 2

    if not PROM.is_file():
        sys.stderr.write(f"missing {PROM}\n")
        return 1
    if not DASH_ROOT.is_dir():
        sys.stderr.write(f"missing {DASH_ROOT}\n")
        return 1

    try:
        hosts = load_hosts(Path(argv[0]))
    except (OSError, ValueError, json.JSONDecodeError) as e:
        sys.stderr.write(f"hosts.json: {e}\n")
        return 1
    if not hosts:
        sys.stderr.write("hosts.json is empty; refusing vacuous host check\n")
        return 1

    jobs = scrape_jobs(PROM)
    unknown_jobs: dict[str, set[str]] = {}
    unknown_hosts: dict[str, set[str]] = {}
    files = 0
    exprs = 0

    dash_files = list(DASH_ROOT.rglob("*.json"))
    files = len(dash_files)
    pairs = collect_exprs()
    exprs = len(pairs)

    for source, expr in pairs:
        for lit in job_literals(expr):
            if lit not in jobs:
                unknown_jobs.setdefault(lit, set()).add(source)
        for op, lit in matcher_literals(expr, HOST_RE):
            if not host_matches_inventory(op, lit, hosts):
                unknown_hosts.setdefault(f"{op}:{lit}", set()).add(source)

    failed = False
    if unknown_jobs:
        failed = True
        sys.stderr.write(
            "PromQL references scrape jobs that are not in "
            f"{PROM.relative_to(ROOT)}:\n"
        )
        for lit in sorted(unknown_jobs):
            where = ", ".join(sorted(unknown_jobs[lit]))
            sys.stderr.write(f"  job={lit!r} in {where}\n")

    if unknown_hosts:
        failed = True
        sys.stderr.write(
            "PromQL host= / host=~ literals match no fleet.inventory.hosts "
            "entry:\n"
        )
        for key in sorted(unknown_hosts):
            where = ", ".join(sorted(unknown_hosts[key]))
            sys.stderr.write(f"  host{key} in {where}\n")

    if failed:
        return 1

    print(
        f"✓ Dashboard/rules job and host names match scrapes/inventory "
        f"({files} dashboards, {exprs} exprs, {len(jobs)} scrape jobs, "
        f"{len(hosts)} hosts)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
