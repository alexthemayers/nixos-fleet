#!/usr/bin/env python3
"""Unit tests for check-alert-rules.py (temp YAML, no flake)."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_alert_rules", ROOT / "scripts" / "check-alert-rules.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def rule(name: str, severity: str | None = "warning", annotations: str | None = None) -> str:
    """One YAML rule item, indented for a `rules:` list."""
    labels = f"labels: {{ severity: {severity} }}" if severity else "labels: {}"
    ann = annotations if annotations is not None else "{ summary: s, description: d }"
    return (
        f"      - alert: {name}\n"
        f'        expr: "1"\n'
        f"        {labels}\n"
        f"        annotations: {ann}\n"
    )


def group(*rules: str, name: str = "g") -> str:
    return f"  - name: {name}\n    rules:\n" + "".join(rules)


def doc(*groups: str) -> str:
    return "groups:\n" + "".join(groups)


class AlertRulesTests(unittest.TestCase):
    def run_checker(self, text: str) -> tuple[int, str]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "rules.yaml"
        path.write_text(text)
        err = io.StringIO()
        with (
            mock.patch("sys.argv", ["check-alert-rules.py", str(path)]),
            contextlib.redirect_stderr(err),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            rc = mod.main()
        return rc, err.getvalue()

    def test_ok(self) -> None:
        rc, err = self.run_checker(doc(group(rule("A"))))
        self.assertEqual((rc, err), (0, ""))

    def test_critical_is_allowed(self) -> None:
        rc, _ = self.run_checker(doc(group(rule("A", "critical"))))
        self.assertEqual(rc, 0)

    def test_same_name_different_severity_is_valid(self) -> None:
        rc, _ = self.run_checker(doc(group(rule("A", "warning"), rule("A", "critical"))))
        self.assertEqual(rc, 0)

    def test_rules_across_groups_are_checked_together(self) -> None:
        rc, err = self.run_checker(
            doc(group(rule("A"), name="one"), group(rule("A"), name="two"))
        )
        self.assertEqual(rc, 1)
        self.assertIn("duplicate alertname/severity: A/warning", err)

    def test_duplicate(self) -> None:
        rc, err = self.run_checker(doc(group(rule("A"), rule("A"))))
        self.assertEqual(rc, 1)
        self.assertIn("duplicate alertname/severity: A/warning", err)

    def test_zero_alerts(self) -> None:
        rc, err = self.run_checker("groups: []\n")
        self.assertEqual(rc, 1)
        self.assertIn("zero alerts", err)

    def test_recording_rules_do_not_count_as_alerts(self) -> None:
        rec = '      - record: r\n        expr: "1"\n'
        rc, err = self.run_checker(doc(group(rec)))
        self.assertEqual(rc, 1)
        self.assertIn("zero alerts", err)

    def test_missing_description(self) -> None:
        rc, err = self.run_checker(
            doc(group(rule("B", "critical", "{ summary: only-summary }")))
        )
        self.assertEqual(rc, 1)
        self.assertIn("no summary/description", err)
        self.assertIn("B", err)

    def test_missing_summary(self) -> None:
        rc, err = self.run_checker(doc(group(rule("C", annotations="{ description: d }"))))
        self.assertEqual(rc, 1)
        self.assertIn("no summary/description", err)

    def test_missing_severity(self) -> None:
        rc, err = self.run_checker(doc(group(rule("D", None))))
        self.assertEqual(rc, 1)
        self.assertIn("severity must be one of critical/warning: D", err)

    def test_unknown_severity(self) -> None:
        rc, err = self.run_checker(doc(group(rule("E", "page"))))
        self.assertEqual(rc, 1)
        self.assertIn("severity must be one of critical/warning: E", err)

    def test_usage_error(self) -> None:
        err = io.StringIO()
        with (
            mock.patch("sys.argv", ["check-alert-rules.py"]),
            contextlib.redirect_stderr(err),
        ):
            self.assertEqual(mod.main(), 2)
        self.assertIn("usage:", err.getvalue())


class RestartCountProducerTests(unittest.TestCase):
    """ServiceCrashLooping reads systemd_service_restart_total, which only
    exists when the systemd exporter runs with enable-restart-count. Debian
    guests and the Proxmox host shipped without it, so the alert could not
    fire there and a restart loop went unseen."""

    RULES = (
        ROOT
        / "collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml"
    )
    PRODUCERS = (
        "config/observability.nix",
        "collections/ansible_collections/fleet/debian_guest/roles/monitoring/templates/systemd-exporter.service.j2",
        "ansible/roles/systemd_exporter/files/unit-filter.conf",
    )

    def test_rules_still_read_the_series(self) -> None:
        self.assertIn("systemd_service_restart_total", self.RULES.read_text(encoding="utf-8"))

    def test_every_systemd_exporter_enables_restart_count(self) -> None:
        for rel in self.PRODUCERS:
            text = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("enable-restart-count", text, f"{rel} lacks enable-restart-count")


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
