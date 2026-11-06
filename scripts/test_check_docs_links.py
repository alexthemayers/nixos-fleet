#!/usr/bin/env python3
"""Unit tests for check-docs-links.py (temp tree, no repo files)."""

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
    "check_docs_links", ROOT / "scripts" / "check-docs-links.py"
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class MakeRefTests(unittest.TestCase):
    def test_inline_code(self) -> None:
        self.assertEqual(mod.make_refs("Run `make lint` first."), {"lint"})

    def test_inline_code_with_dollar(self) -> None:
        self.assertEqual(mod.make_refs("Run `$ make fmt-check`."), {"fmt-check"})

    def test_fenced_lines(self) -> None:
        text = "```bash\nmake deploy-host HOST=x\n  $ make ci\nls\n```\n"
        self.assertEqual(mod.make_refs(text), {"deploy-host", "ci"})

    def test_prose_is_ignored(self) -> None:
        self.assertEqual(mod.make_refs("We make it work and make worse."), set())

    def test_command_after_and_in_span(self) -> None:
        self.assertEqual(mod.make_refs("`cd x && make foo`"), {"foo"})

    def test_command_after_semicolon_and_pipe_in_span(self) -> None:
        self.assertEqual(mod.make_refs("`a; make b` and `c | make d`"), {"b", "d"})

    def test_make_inside_a_word_is_ignored(self) -> None:
        self.assertEqual(mod.make_refs("`cmake build` and `remake x`"), set())

    def test_glob_is_ignored(self) -> None:
        self.assertEqual(mod.make_refs("a dedicated `make check-*` target"), set())

    def test_make_outside_fence_line_start_is_ignored(self) -> None:
        self.assertEqual(mod.make_refs("make lint\n"), set())


class MakeTargetTests(unittest.TestCase):
    def test_targets_exclude_variable_assignments(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        (Path(tmp.name) / "Makefile").write_text(
            "HOSTS := a b\n.PHONY: lint ci\nlint:\n\techo\nci: lint\n\techo\n"
        )
        with mock.patch.object(mod, "ROOT", Path(tmp.name)):
            self.assertEqual(mod.make_targets(), {"lint", "ci"})


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
            contextlib.redirect_stderr(err),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            rc = mod.main()
        return rc, err.getvalue()

    def test_ok(self) -> None:
        rc, err = self.run_tree(
            {
                "Makefile": "lint:\n\techo\n",
                "scripts/a.sh": "",
                "docs/a.md": "See [b](b.md), `make lint`, scripts/a.sh.\n",
                "docs/b.md": "# b\n",
            }
        )
        self.assertEqual((rc, err), (0, ""))

    def test_broken_link(self) -> None:
        rc, err = self.run_tree({"Makefile": "", "docs/a.md": "[x](gone.md)\n"})
        self.assertEqual(rc, 1)
        self.assertIn("docs/a.md: missing gone.md", err)

    def test_missing_script(self) -> None:
        rc, err = self.run_tree({"Makefile": "", "docs/a.md": "`scripts/gone.sh`\n"})
        self.assertEqual(rc, 1)
        self.assertIn("missing scripts/gone.sh", err)

    def test_missing_make_target(self) -> None:
        rc, err = self.run_tree(
            {"Makefile": "lint:\n\techo\n", "docs/a.md": "Run `make deploy-proxmox`.\n"}
        )
        self.assertEqual(rc, 1)
        self.assertIn("no Makefile target `deploy-proxmox`", err)

    def test_adr_is_historical_and_skipped(self) -> None:
        rc, err = self.run_tree(
            {
                "Makefile": "",
                "docs/adr/old.md": "[x](gone.md) `make removed` `scripts/gone.sh`\n",
            }
        )
        self.assertEqual((rc, err), (0, ""))


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
