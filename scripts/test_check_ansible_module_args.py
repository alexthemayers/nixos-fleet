#!/usr/bin/env python3
"""Unit tests for check-ansible-module-args.py (no ansible-doc needed)."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_ansible_module_args", ROOT / "scripts" / "check-ansible-module-args.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

REL = Path("roles/x/tasks/main.yml")
KWS = {"name", "when", "loop", "notify", "register", "block", "rescue", "always", "vars", "args"}
ACCEPTED = {
    "ansible.builtin.copy": {"src", "dest", "mode", "owner", "content", "path"},
    "ansible.builtin.file": {"path", "state", "dest", "name"},
}


def problems(task: dict) -> list[str]:
    return mod.check_task(task, REL, KWS, ACCEPTED)


class CheckTaskTests(unittest.TestCase):
    def test_valid_args(self) -> None:
        task = {"name": "t", "ansible.builtin.copy": {"src": "a", "dest": "b"}, "notify": "x"}
        self.assertEqual(problems(task), [])

    def test_unknown_option_is_reported(self) -> None:
        task = {"name": "t", "ansible.builtin.copy": {"src": "a", "dest": "b", "delete": True}}
        (msg,) = problems(task)
        self.assertIn("no option 'delete'", msg)
        self.assertIn("ansible.builtin.copy", msg)

    def test_alias_is_accepted(self) -> None:
        task = {"name": "t", "ansible.builtin.file": {"name": "/x", "state": "absent"}}
        self.assertEqual(problems(task), [])

    def test_task_keywords_are_not_module_args(self) -> None:
        task = {
            "name": "t",
            "when": "x",
            "ansible.builtin.file": {"path": "/x", "state": "absent"},
            "loop": [1],
        }
        self.assertEqual(problems(task), [])

    def test_string_args_are_skipped(self) -> None:
        self.assertEqual(problems({"name": "t", "ansible.builtin.copy": "free form"}), [])

    def test_free_form_module_is_skipped(self) -> None:
        self.assertEqual(problems({"ansible.builtin.set_fact": {"anything": 1}}), [])

    def test_short_module_name_is_skipped(self) -> None:
        self.assertEqual(problems({"copy": {"delete": True}}), [])

    def test_templated_key_is_skipped(self) -> None:
        task = {"ansible.builtin.copy": {"src": "a", "dest": "b", "{{ k }}": 1}}
        self.assertEqual(problems(task), [])

    def test_unknown_module_is_reported(self) -> None:
        (msg,) = problems({"name": "t", "community.nope.thing": {"a": 1}})
        self.assertIn("does not know module", msg)


class IterTasksTests(unittest.TestCase):
    def test_blocks_and_plays_are_walked(self) -> None:
        doc = [
            {
                "hosts": "all",
                "tasks": [
                    {"name": "a", "ansible.builtin.file": {"path": "/a"}},
                    {
                        "block": [{"name": "b", "ansible.builtin.file": {"path": "/b"}}],
                        "rescue": [{"name": "c", "ansible.builtin.file": {"path": "/c"}}],
                    },
                ],
                "handlers": [{"name": "d", "ansible.builtin.file": {"path": "/d"}}],
            }
        ]
        names = [t.get("name") for t in mod.iter_tasks(doc) if "name" in t]
        self.assertEqual(sorted(names), ["a", "b", "c", "d"])

    def test_module_of_skips_keywords(self) -> None:
        task = {"name": "t", "when": "x", "ansible.builtin.copy": {}}
        self.assertEqual(mod.module_of(task, KWS), "ansible.builtin.copy")

    def test_module_of_none_for_block(self) -> None:
        self.assertIsNone(mod.module_of({"block": [], "name": "t"}, KWS))

    def test_repo_trees_contain_tasks(self) -> None:
        count = 0
        for path in mod.yaml_files():
            import yaml

            for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")):
                count += sum(1 for _ in mod.iter_tasks(doc or []))
        self.assertGreater(count, 100)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
