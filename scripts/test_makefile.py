#!/usr/bin/env python3
"""Structural tests for the root Makefile and the `ci` gate.

Catches a gate that silently loses a check: a `ci` prerequisite that is not
a target, a target missing from .PHONY, or a scripts/test_*.py suite and
scripts/check-*.{sh,py} checker that no `ci` prerequisite runs.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT = (ROOT / "Makefile").read_text(encoding="utf-8")

TARGET_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_.-]*)\s*:(?!=)(.*)$", re.MULTILINE)


def targets() -> dict[str, tuple[list[str], str]]:
    """target -> (prerequisites, recipe text)."""
    found: dict[str, tuple[list[str], str]] = {}
    matches = list(TARGET_RE.finditer(TEXT))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(TEXT)
        recipe = TEXT[m.end() : end]
        found[m.group(1)] = (m.group(2).split(), recipe)
    return found


def phony() -> set[str]:
    m = re.search(r"^\.PHONY:(.*)$", TEXT, re.MULTILINE)
    assert m, "Makefile has no .PHONY line"
    return set(m.group(1).split())


# Checkers that are deliberately not in `ci`, with the reason.
NOT_IN_CI = {
    "check-live-promql.sh": "needs the live Prometheus; GitLab live-promql job",
    "check-secrets.sh": "needs the operator age key; CI runs check-secrets-keys",
    "check-alertmanager-config.sh": "run via check-obs-config",
    "check-prometheus-rules.sh": "run via check-obs-config",
    "check-debian-inventory.sh": "run via check-inventory",
}


class MakefileTests(unittest.TestCase):
    def test_ci_exists_and_has_prerequisites(self) -> None:
        self.assertIn("ci", targets())
        self.assertGreater(len(targets()["ci"][0]), 5)

    def test_every_ci_prerequisite_is_a_target(self) -> None:
        defined = targets()
        for prereq in defined["ci"][0]:
            self.assertIn(prereq, defined, f"ci needs undefined target {prereq}")

    def test_every_target_is_phony(self) -> None:
        missing = sorted(set(targets()) - phony())
        self.assertEqual(missing, [], "targets missing from .PHONY")

    def test_phony_has_no_stale_names(self) -> None:
        stale = sorted(phony() - set(targets()))
        self.assertEqual(stale, [], ".PHONY names with no target")

    def test_removed_targets_stay_removed(self) -> None:
        for name in ("deploy-proxmox", "deploy-rs", "check-mimir-rules"):
            self.assertNotIn(name, targets())
            self.assertNotIn(name, phony())

    def test_every_test_suite_runs_in_ci(self) -> None:
        defined = targets()
        ci = set(defined["ci"][0])
        for suite in sorted((ROOT / "scripts").glob("test_*.py")):
            runners = [
                t for t, (_, recipe) in defined.items() if f"scripts/{suite.name}" in recipe
            ]
            self.assertTrue(runners, f"no Make target runs {suite.name}")
            self.assertTrue(
                ci.intersection(runners), f"{suite.name} not reached by `make ci`"
            )

    def test_every_checker_is_wired(self) -> None:
        defined = targets()
        ci = set(defined["ci"][0])
        for checker in sorted((ROOT / "scripts").glob("check-*")):
            if checker.suffix not in {".sh", ".py"}:
                continue
            runners = {
                t for t, (_, recipe) in defined.items() if f"scripts/{checker.name}" in recipe
            }
            in_scripts = any(
                checker.name in other.read_text(encoding="utf-8")
                for other in (ROOT / "scripts").glob("*.sh")
                if other != checker
            )
            if checker.name in NOT_IN_CI:
                continue
            self.assertTrue(
                runners or in_scripts, f"{checker.name} is not run by any target"
            )
            self.assertTrue(
                ci.intersection(runners) or in_scripts,
                f"{checker.name} is not reached by `make ci`",
            )


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
