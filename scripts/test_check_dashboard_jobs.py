#!/usr/bin/env python3
"""Unit tests for check-dashboard-jobs.py helpers (no flake eval)."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_dashboard_jobs", ROOT / "scripts" / "check-dashboard-jobs.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class HostMatchTests(unittest.TestCase):
    hosts = {
        "proxmox-applications-debian",
        "proxmox-observability-debian",
        "gaming",
        "xcloud-caddy",
    }

    def test_exact_match(self) -> None:
        self.assertTrue(
            mod.host_matches_inventory("=", "gaming", self.hosts)
        )
        self.assertFalse(
            mod.host_matches_inventory("=", "proxmox-applications-1", self.hosts)
        )

    def test_regex_matches_at_least_one(self) -> None:
        self.assertTrue(
            mod.host_matches_inventory("=~", "proxmox-.*", self.hosts)
        )
        self.assertFalse(
            mod.host_matches_inventory("=~", "rpi4.*", self.hosts)
        )

    def test_invalid_regex_fails(self) -> None:
        self.assertFalse(
            mod.host_matches_inventory("=~", "[unterminated", self.hosts)
        )


class LiteralExtractTests(unittest.TestCase):
    def test_job_and_host(self) -> None:
        expr = (
            'up{job="node",host="gaming"} + '
            'rate(x{job=~"node|systemd",host=~"proxmox-.*"}[5m])'
        )
        self.assertEqual(sorted(set(mod.job_literals(expr))), ["node", "systemd"])
        pairs = mod.matcher_literals(expr, mod.HOST_RE)
        self.assertEqual(
            sorted(pairs),
            [("=", "gaming"), ("=~", "proxmox-.*")],
        )

    def test_skips_variables(self) -> None:
        expr = 'up{job="$job",host="$host"}'
        self.assertEqual(mod.job_literals(expr), [])
        self.assertEqual(mod.matcher_literals(expr, mod.HOST_RE), [])


class LoadHostsTests(unittest.TestCase):
    def test_load_list(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write('["a", "b"]\n')
            path = Path(f.name)
        try:
            self.assertEqual(mod.load_hosts(path), {"a", "b"})
        finally:
            path.unlink()


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
