#!/usr/bin/env python3
"""Unit tests for check-prometheus-scrapes.py helpers."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_prometheus_scrapes", ROOT / "scripts" / "check-prometheus-scrapes.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class HostOfTests(unittest.TestCase):
    def test_host_port(self) -> None:
        self.assertEqual(mod.host_of("gaming:9100"), "gaming")

    def test_url(self) -> None:
        self.assertEqual(mod.host_of("https://immich.example/"), "immich.example")


class ScrapeHostTests(unittest.TestCase):
    def test_url_not_host_target(self) -> None:
        self.assertFalse(mod.is_scrape_host_target("https://x"))

    def test_host_target(self) -> None:
        self.assertTrue(mod.is_scrape_host_target("gaming:9100"))


class MainTests(unittest.TestCase):
    def test_unknown_host_fails(self) -> None:
        prom = tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False)
        hosts = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        try:
            prom.write(
                "scrape_configs:\n"
                "  - job_name: node\n"
                "    relabel_configs:\n"
                "      - target_label: host\n"
                "    static_configs:\n"
                "      - targets: [ghost:9100]\n"
            )
            prom.close()
            hosts.write('["gaming"]\n')
            hosts.close()
            import sys

            old = sys.argv
            sys.argv = ["check-prometheus-scrapes.py", prom.name, hosts.name]
            try:
                self.assertEqual(mod.main(), 1)
            finally:
                sys.argv = old
        finally:
            Path(prom.name).unlink(missing_ok=True)
            Path(hosts.name).unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
