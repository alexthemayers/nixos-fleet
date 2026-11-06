#!/usr/bin/env python3
"""Unit tests for check-alert-rules.py (temp YAML, no flake)."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_alert_rules", ROOT / "scripts" / "check-alert-rules.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


GOOD = """
groups:
  - name: t
    rules:
      - alert: A
        expr: "1"
        labels: { severity: warning }
        annotations: { summary: s, description: d }
"""

DUP = """
groups:
  - name: t
    rules:
      - alert: A
        expr: "1"
        labels: { severity: warning }
        annotations: { summary: s, description: d }
      - alert: A
        expr: "2"
        labels: { severity: warning }
        annotations: { summary: s2, description: d2 }
"""

MISSING = """
groups:
  - name: t
    rules:
      - alert: B
        expr: "1"
        labels: { severity: critical }
        annotations: { summary: only-summary }
"""


class AlertRulesTests(unittest.TestCase):
    def _run(self, text: str) -> int:
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
            f.write(text)
            path = f.name
        old = sys.argv
        sys.argv = ["check-alert-rules.py", path]
        try:
            return mod.main()
        finally:
            sys.argv = old
            Path(path).unlink(missing_ok=True)

    def test_ok(self) -> None:
        self.assertEqual(self._run(GOOD), 0)

    def test_duplicate(self) -> None:
        self.assertEqual(self._run(DUP), 1)

    def test_missing_annotation(self) -> None:
        self.assertEqual(self._run(MISSING), 1)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
