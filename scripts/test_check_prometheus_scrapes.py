#!/usr/bin/env python3
"""Unit tests for check-prometheus-scrapes.py."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_prometheus_scrapes", ROOT / "scripts" / "check-prometheus-scrapes.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

HOST_RELABEL = "    relabel_configs:\n      - target_label: host\n"


def job(name: str, *target_lists: list[str], relabel: bool = True) -> str:
    out = f"  - job_name: {name}\n"
    if relabel:
        out += HOST_RELABEL
    out += "    static_configs:\n"
    for targets in target_lists:
        out += f"      - targets: {json.dumps(targets)}\n"
    return out


def prom(*jobs: str) -> str:
    return "scrape_configs:\n" + "".join(jobs)


class HostOfTests(unittest.TestCase):
    def test_host_port(self) -> None:
        self.assertEqual(mod.host_of("gaming:9100"), "gaming")

    def test_bare_host(self) -> None:
        self.assertEqual(mod.host_of("gaming"), "gaming")

    def test_url(self) -> None:
        self.assertEqual(mod.host_of("https://immich.example/"), "immich.example")


class ScrapeHostTests(unittest.TestCase):
    def test_url_not_host_target(self) -> None:
        self.assertFalse(mod.is_scrape_host_target("https://x"))

    def test_host_target(self) -> None:
        self.assertTrue(mod.is_scrape_host_target("gaming:9100"))


class MainTests(unittest.TestCase):
    def run_checker(self, prom_text: str, hosts: list[str]) -> tuple[int, str]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        prom_path = Path(tmp.name) / "prometheus.yml"
        hosts_path = Path(tmp.name) / "hosts.json"
        prom_path.write_text(prom_text)
        hosts_path.write_text(json.dumps(hosts))
        err = io.StringIO()
        with (
            mock.patch("sys.argv", ["check-prometheus-scrapes.py", str(prom_path), str(hosts_path)]),
            contextlib.redirect_stderr(err),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            rc = mod.main()
        return rc, err.getvalue()

    def test_ok(self) -> None:
        rc, err = self.run_checker(prom(job("node", ["gaming:9100"])), ["gaming"])
        self.assertEqual((rc, err), (0, ""))

    def test_unknown_host_fails(self) -> None:
        rc, err = self.run_checker(prom(job("node", ["ghost:9100"])), ["gaming"])
        self.assertEqual(rc, 1)
        self.assertIn("node:ghost:9100", err)

    def test_zero_scrape_configs_fails(self) -> None:
        rc, err = self.run_checker("scrape_configs: []\n", ["gaming"])
        self.assertEqual(rc, 1)
        self.assertIn("zero scrape_configs", err)

    def test_missing_host_relabel_fails(self) -> None:
        rc, err = self.run_checker(
            prom(job("node", ["gaming:9100"], relabel=False)), ["gaming"]
        )
        self.assertEqual(rc, 1)
        self.assertIn("Missing relabel_configs host", err)
        self.assertIn("node", err)

    def test_blackbox_url_probe_is_exempt(self) -> None:
        text = prom(job("blackbox_http", ["https://x.example/"], relabel=False))
        rc, err = self.run_checker(text, ["gaming"])
        self.assertEqual((rc, err), (0, ""))

    def test_localhost_targets_are_exempt(self) -> None:
        text = prom(job("self", ["localhost:9090", "127.0.0.1:9093"]))
        rc, err = self.run_checker(text, ["gaming"])
        self.assertEqual((rc, err), (0, ""))

    def test_multiple_static_configs_are_all_checked(self) -> None:
        text = prom(job("node", ["gaming:9100"], ["ghost:9100"]))
        rc, err = self.run_checker(text, ["gaming"])
        self.assertEqual(rc, 1)
        self.assertIn("ghost:9100", err)

    def test_duplicate_unknown_target_reported_once(self) -> None:
        text = prom(job("node", ["ghost:9100", "ghost:9100"]))
        _, err = self.run_checker(text, ["gaming"])
        self.assertEqual(err.count("node:ghost:9100"), 1)

    def test_empty_targets_pass(self) -> None:
        rc, err = self.run_checker(prom(job("node", [])), ["gaming"])
        self.assertEqual((rc, err), (0, ""))

    def test_usage_error(self) -> None:
        err = io.StringIO()
        with (
            mock.patch("sys.argv", ["check-prometheus-scrapes.py"]),
            contextlib.redirect_stderr(err),
        ):
            self.assertEqual(mod.main(), 2)
        self.assertIn("usage:", err.getvalue())


class ApplyHandlerTests(unittest.TestCase):
    """Config and rules are single-file bind mounts; `copy` swaps the inode, so
    /-/reload would re-read the old file. The role must restart the unit."""

    ROLE = ROOT / "collections/ansible_collections/fleet/debian_guest/roles/observability"

    def test_config_changes_restart_prometheus(self) -> None:
        tasks = (self.ROLE / "tasks/main.yml").read_text(encoding="utf-8")
        handlers = (self.ROLE / "handlers/main.yml").read_text(encoding="utf-8")
        self.assertIn("notify: Restart Prometheus", tasks)
        self.assertIn("- name: Restart Prometheus", handlers)
        self.assertNotIn("url: http://127.0.0.1:9090/-/reload", handlers)
        self.assertNotIn("notify: Reload Prometheus", tasks)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
