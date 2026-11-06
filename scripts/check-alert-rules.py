#!/usr/bin/env python3
"""Fail on duplicate alertname/severity or missing summary/description.

The ntfy webhook builds every push from annotations.summary and
annotations.description. A collision on both alertname and severity makes
two rules indistinguishable in routing and silences.
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

try:
    import yaml
except ImportError:
    # PyYAML is not on the Darwin checkout PATH. Prefer the stdlib-safe
    # subset: rules.yaml is generated and only needs mapping/list access.
    sys.stderr.write("check-alert-rules.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write(f"usage: {sys.argv[0]} <rules.yaml>\n")
        return 2
    path = Path(sys.argv[1])
    data = yaml.safe_load(path.read_text())
    groups = data.get("groups") or []
    alerts = []
    for group in groups:
        for rule in group.get("rules") or []:
            if "alert" in rule:
                alerts.append(rule)

    keys = [
        f"{r['alert']}/{(r.get('labels') or {}).get('severity', '<none>')}" for r in alerts
    ]
    duplicates = sorted(k for k, n in Counter(keys).items() if n > 1)

    unannotated = sorted(
        {
            r["alert"]
            for r in alerts
            if not ((r.get("annotations") or {}).get("summary"))
            or not ((r.get("annotations") or {}).get("description"))
        }
    )

    problems = []
    if duplicates:
        problems.append("duplicate alertname/severity: " + ", ".join(duplicates))
    if unannotated:
        problems.append(
            "no summary/description, so ntfy would send an empty body: "
            + ", ".join(unannotated)
        )
    if problems:
        sys.stderr.write(f"{path}: " + "; ".join(problems) + "\n")
        return 1
    print(f"{path}: {len(alerts)} alerts ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
