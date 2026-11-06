#!/usr/bin/env python3
"""Unit tests for pure helpers in router-reboot.py (no live router)."""

from __future__ import annotations

import datetime
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "router_reboot", ROOT / "scripts" / "router-reboot.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class QuietWindowTests(unittest.TestCase):
    def test_inside_window(self) -> None:
        now = datetime.datetime(2026, 11, 6, 3, 0, 0)
        self.assertTrue(mod.in_quiet_window(now))

    def test_before_window(self) -> None:
        now = datetime.datetime(2026, 11, 6, 1, 29, 0)
        self.assertFalse(mod.in_quiet_window(now))

    def test_after_window(self) -> None:
        now = datetime.datetime(2026, 11, 6, 5, 31, 0)
        self.assertFalse(mod.in_quiet_window(now))

    def test_boundaries_inclusive(self) -> None:
        self.assertTrue(mod.in_quiet_window(datetime.datetime(2026, 11, 6, 1, 30, 0)))
        self.assertTrue(mod.in_quiet_window(datetime.datetime(2026, 11, 6, 5, 30, 0)))


class ScramProofTests(unittest.TestCase):
    def test_deterministic_shape(self) -> None:
        proof, server_sig, server_key = mod.scram_proof(
            "password",
            "aabbccdd",
            4096,
            "aa" * 32,
            "bb" * 32,
        )
        self.assertEqual(len(proof), 64)
        self.assertEqual(len(server_sig), 64)
        self.assertEqual(len(server_key), 32)
        # Same inputs → same proof.
        proof2, _, _ = mod.scram_proof(
            "password",
            "aabbccdd",
            4096,
            "aa" * 32,
            "bb" * 32,
        )
        self.assertEqual(proof, proof2)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
