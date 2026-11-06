#!/usr/bin/env python3
"""Fail on broken relative markdown links, missing scripts/* refs, and
`make <target>` commands that the root Makefile does not define.

Covers docs/, README.md, AGENTS.md, .cursor/. ADRs are historical: links are
not checked, and scripts/* and make targets are not checked either.
Only code spans and fenced code lines are read as make commands, so prose
such as "make it work" is ignored.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"\]\(([^)#\s]+)(#[^)]*)?\)")
SCRIPT_RE = re.compile(r"(?:^|[\s`\"'(])/?(scripts/[A-Za-z0-9_.-]+\.(?:sh|py))\b")

# `make foo` anywhere in an inline code span (after `&&`, `;`, `||` or a pipe
# too), or on a fenced line that starts with make (optionally after "$ ").
CODE_SPAN_RE = re.compile(r"`([^`\n]+)`")
MAKE_CMD_RE = re.compile(
    r"(?:^|&&|\|\||;|\|)\s*(?:\$ )?make\s+([a-z][a-z0-9_-]*)(?![a-z0-9_*-])"
)
MAKE_LINE_RE = re.compile(r"^\s*(?:\$ )?make\s+([a-z][a-z0-9_-]*)(?![a-z0-9_*-])")
MAKE_TARGET_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_.-]*)\s*:(?!=)", re.MULTILINE)

SKIP_PREFIXES = (
    "http://",
    "https://",
    "mailto:",
)


def make_targets() -> set[str]:
    return set(MAKE_TARGET_RE.findall((ROOT / "Makefile").read_text(encoding="utf-8")))


def make_refs(text: str) -> set[str]:
    refs: set[str] = set()
    for span in CODE_SPAN_RE.findall(text):
        refs.update(MAKE_CMD_RE.findall(span))
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            m = MAKE_LINE_RE.match(line)
            if m:
                refs.add(m.group(1))
    return refs


def iter_files() -> list[Path]:
    out: list[Path] = []
    for pattern in ("docs/**/*.md", "docs/**/*.mdc", ".cursor/**/*.md", ".cursor/**/*.mdc"):
        out.extend(ROOT.glob(pattern))
    for name in ("README.md", "AGENTS.md"):
        p = ROOT / name
        if p.is_file():
            out.append(p)
    return sorted({p.resolve() for p in out if p.is_file()})


def is_adr(path: Path) -> bool:
    try:
        return path.relative_to(ROOT / "docs" / "adr") is not None
    except ValueError:
        return False


def main() -> int:
    broken: list[str] = []
    missing_scripts: list[str] = []
    missing_make: list[str] = []
    targets = make_targets()

    for path in iter_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = path.relative_to(ROOT)
        adr = is_adr(path)

        # ADRs keep historical links to deleted stubs; do not fail those.
        if not adr:
            for m in LINK_RE.finditer(text):
                target = m.group(1)
                if target.startswith(SKIP_PREFIXES) or target.startswith("#"):
                    continue
                # template placeholders in adr-template
                if "YYYY-MM-DD" in target:
                    continue
                resolved = (path.parent / target).resolve()
                try:
                    resolved.relative_to(ROOT)
                except ValueError:
                    broken.append(f"{rel}: link escapes repo: {target}")
                    continue
                if not resolved.exists():
                    broken.append(f"{rel}: missing {target}")

            for m in SCRIPT_RE.finditer(text):
                script = m.group(1)
                if not (ROOT / script).is_file():
                    missing_scripts.append(f"{rel}: missing {script}")

            for target in make_refs(text):
                if target not in targets:
                    missing_make.append(f"{rel}: no Makefile target `{target}`")

    failed = False
    if broken:
        failed = True
        sys.stderr.write("Broken relative markdown links:\n")
        for line in sorted(set(broken)):
            sys.stderr.write(f"  {line}\n")
    if missing_scripts:
        failed = True
        sys.stderr.write("Missing scripts/* references:\n")
        for line in sorted(set(missing_scripts)):
            sys.stderr.write(f"  {line}\n")
    if missing_make:
        failed = True
        sys.stderr.write("Documented make targets missing from Makefile:\n")
        for line in sorted(set(missing_make)):
            sys.stderr.write(f"  {line}\n")
    if failed:
        return 1
    print(f"✓ Doc links, script refs and make targets ok ({len(iter_files())} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
