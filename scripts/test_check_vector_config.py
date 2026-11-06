#!/usr/bin/env python3
"""Unit tests for check-vector-config.py drift detection (no nix, no ansible)."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_vector_config", ROOT / "scripts" / "check-vector-config.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

VRL = 'host_name = "@host@"\n. = {"host": host_name}\n'
SINK = {
    "type": "loki",
    "labels": {"host": "{{ host }}"},
    "buffer": {"type": "disk", "max_size": 268435488, "when_full": "block"},
}


def good_config(host: str = "gaming") -> dict:
    return {
        "sources": {"journald": {"type": "journald"}},
        "transforms": {
            "journal_remap": {"type": "remap", "source": VRL.replace("@host@", host)}
        },
        "sinks": {
            "loki": {**SINK, "inputs": ["journal_remap"], "endpoint": "http://loki:3100"},
            "prometheus_exporter": {"type": "prometheus_exporter", "address": "0.0.0.0:9598"},
        },
    }


class DriftTests(unittest.TestCase):
    def drift(self, cfg: dict, host: str = "gaming") -> list[str]:
        return mod.drift("t", cfg, host, VRL, SINK)

    def test_clean(self) -> None:
        self.assertEqual(self.drift(good_config()), [])

    def test_extra_inputs_are_allowed(self) -> None:
        cfg = good_config()
        cfg["sinks"]["loki"]["inputs"].append("postgres_remap")
        self.assertEqual(self.drift(cfg), [])

    def test_vrl_drift(self) -> None:
        cfg = good_config()
        cfg["transforms"]["journal_remap"]["source"] += ".extra = 1\n"
        self.assertTrue(any("journal_remap.source differs" in p for p in self.drift(cfg)))

    def test_wrong_host_substitution(self) -> None:
        cfg = good_config("other")
        self.assertTrue(any("journal_remap.source differs" in p for p in self.drift(cfg)))

    def test_missing_remap(self) -> None:
        cfg = good_config()
        del cfg["transforms"]
        self.assertTrue(any("no transforms.journal_remap.source" in p for p in self.drift(cfg)))

    def test_sink_label_drift(self) -> None:
        cfg = good_config()
        cfg["sinks"]["loki"]["labels"] = {"host": "{{ host }}", "extra": "x"}
        self.assertTrue(any("sinks.loki differs" in p for p in self.drift(cfg)))

    def test_sink_buffer_drift(self) -> None:
        cfg = good_config()
        cfg["sinks"]["loki"]["buffer"] = {"type": "memory"}
        self.assertTrue(any("sinks.loki differs" in p for p in self.drift(cfg)))

    def test_missing_endpoint(self) -> None:
        cfg = good_config()
        del cfg["sinks"]["loki"]["endpoint"]
        self.assertTrue(any("endpoint missing" in p for p in self.drift(cfg)))

    def test_exporter_address(self) -> None:
        cfg = good_config()
        cfg["sinks"]["prometheus_exporter"]["address"] = "127.0.0.1:9598"
        self.assertTrue(any("9598" in p for p in self.drift(cfg)))

    def test_missing_journald(self) -> None:
        cfg = good_config()
        cfg["sources"] = {}
        self.assertTrue(any("no journald source" in p for p in self.drift(cfg)))

    def test_input_config_is_not_mutated(self) -> None:
        cfg = good_config()
        before = copy.deepcopy(cfg)
        self.drift(cfg)
        self.assertEqual(cfg, before)


class SharedFilesTests(unittest.TestCase):
    def test_vrl_has_host_placeholder(self) -> None:
        self.assertIn("@host@", (mod.SHARED / "journal-remap.vrl").read_text())

    def test_sink_json_is_a_loki_sink(self) -> None:
        sink = json.loads((mod.SHARED / "loki-sink.json").read_text())
        self.assertEqual(sink["type"], "loki")
        self.assertEqual(
            sorted(sink["labels"]),
            ["host", "job", "service", "syslog_facility", "syslog_id"],
        )
        self.assertEqual(sink["buffer"]["when_full"], "block")
        for key in mod.SINK_LOCAL_KEYS:
            self.assertNotIn(key, sink)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
