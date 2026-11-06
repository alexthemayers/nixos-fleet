#!/usr/bin/env python3
"""Unit tests for check-ansible-downloads.py (temp trees, no repo files)."""

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
    "check_ansible_downloads", ROOT / "scripts" / "check-ansible-downloads.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

GOOD_TASK = """
- name: Fetch key
  ansible.builtin.get_url:
    url: https://example.test/key
    dest: /usr/share/keyrings/k.asc
    checksum: "sha256:{{ key_sha256 }}"
"""
DEFAULTS = "key_sha256: abc123\n"


class CheckTaskTests(unittest.TestCase):
    def problems(self, task: dict, known: set[str] | None = None) -> list[str]:
        return mod.check_task(task, Path("t.yml"), known or set())

    def test_get_url_with_checksum_ok(self) -> None:
        task = {"name": "x", "ansible.builtin.get_url": {"checksum": "sha256:aa"}}
        self.assertEqual(self.problems(task), [])

    def test_get_url_without_checksum(self) -> None:
        task = {"name": "x", "ansible.builtin.get_url": {"url": "https://x"}}
        self.assertIn("has no checksum", self.problems(task)[0])

    def test_get_url_blank_checksum(self) -> None:
        task = {"name": "x", "get_url": {"checksum": "  "}}
        self.assertIn("has no checksum", self.problems(task)[0])

    def test_undefined_checksum_variable(self) -> None:
        task = {"name": "x", "get_url": {"checksum": "sha256:{{ nope }}"}}
        self.assertIn("undefined variable nope", self.problems(task)[0])

    def test_defined_checksum_variable(self) -> None:
        task = {"name": "x", "get_url": {"checksum": "sha256:{{ yes }}"}}
        self.assertEqual(self.problems(task, {"yes"}), [])

    def test_signed_by_url(self) -> None:
        task = {
            "name": "repo",
            "ansible.builtin.deb822_repository": {"signed_by": "https://k.test/key"},
        }
        self.assertIn("signed_by is a URL", self.problems(task)[0])

    def test_signed_by_path_ok(self) -> None:
        task = {
            "name": "repo",
            "ansible.builtin.deb822_repository": {"signed_by": "/usr/share/keyrings/k.asc"},
        }
        self.assertEqual(self.problems(task), [])

    def test_apt_key_rejected(self) -> None:
        task = {"name": "key", "ansible.builtin.apt_key": {"url": "https://k.test"}}
        self.assertIn("uses apt_key", self.problems(task)[0])


class RequirementsTests(unittest.TestCase):
    def test_pinned_ok(self) -> None:
        docs = [{"collections": [{"name": "a.b", "version": "1.0.0"}]}]
        self.assertEqual(mod.check_requirements(docs, Path("r.yml")), [])

    def test_unpinned_entry(self) -> None:
        docs = [{"collections": [{"name": "a.b"}]}]
        self.assertIn("a.b has no version", mod.check_requirements(docs, Path("r.yml"))[0])

    def test_bare_string_entry(self) -> None:
        docs = [{"collections": ["a.b"]}]
        self.assertIn("a.b has no version", mod.check_requirements(docs, Path("r.yml"))[0])


class MainTests(unittest.TestCase):
    def run_tree(self, files: dict[str, str]) -> tuple[int, str]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name).resolve()
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        err = io.StringIO()
        with (
            mock.patch.object(mod, "ROOT", root),
            mock.patch.object(mod, "TREES", ("ansible",)),
            contextlib.redirect_stderr(err),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            rc = mod.main()
        return rc, err.getvalue()

    def test_ok_tree(self) -> None:
        rc, err = self.run_tree(
            {
                "ansible/roles/r/tasks/main.yml": GOOD_TASK,
                "ansible/roles/r/defaults/main.yml": DEFAULTS,
            }
        )
        self.assertEqual((rc, err), (0, ""))

    def test_nested_block_task_is_found(self) -> None:
        nested = (
            "- name: b\n  block:\n    - name: inner\n      get_url:\n        url: https://x\n"
        )
        rc, err = self.run_tree({"ansible/roles/r/tasks/main.yml": nested})
        self.assertEqual(rc, 1)
        self.assertIn("'inner' has no checksum", err)

    def test_undefined_variable_in_tree(self) -> None:
        rc, err = self.run_tree({"ansible/roles/r/tasks/main.yml": GOOD_TASK})
        self.assertEqual(rc, 1)
        self.assertIn("undefined variable key_sha256", err)

    def test_zero_get_url_fails_the_scan(self) -> None:
        rc, err = self.run_tree({"ansible/roles/r/tasks/main.yml": "- name: n\n  debug: {}\n"})
        self.assertEqual(rc, 1)
        self.assertIn("zero get_url tasks", err)

    def test_files_and_templates_are_skipped(self) -> None:
        rc, _ = self.run_tree(
            {
                "ansible/roles/r/tasks/main.yml": GOOD_TASK,
                "ansible/roles/r/defaults/main.yml": DEFAULTS,
                "ansible/roles/r/files/payload.yml": "- get_url: {url: https://x}\n",
            }
        )
        self.assertEqual(rc, 0)

    def test_unpinned_requirements_fail(self) -> None:
        rc, err = self.run_tree(
            {
                "ansible/roles/r/tasks/main.yml": GOOD_TASK,
                "ansible/roles/r/defaults/main.yml": DEFAULTS,
                "ansible/requirements.yml": "collections:\n  - name: a.b\n",
            }
        )
        self.assertEqual(rc, 1)
        self.assertIn("a.b has no version", err)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
