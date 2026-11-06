#!/usr/bin/env python3
"""Fail when Ansible fetches something it does not verify.

Rules (docs/adr/2026-11-06-pin-ansible-downloads.md):

- every get_url sets a non-empty `checksum`, and a templated checksum names a
  variable that is defined in a defaults/ or vars file
- no deb822_repository / apt_repository `signed_by` is a URL; apt would fetch
  the key unpinned. Download it with get_url + checksum and use the path
- no apt_key module
- every Galaxy collection in a requirements.yml has a `version`

Scans tasks, handlers, playbooks, defaults, group_vars, host_vars and
requirements under ansible/ and the debian_guest collection. Skips files/
and templates/ (payloads, not tasks).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any, Iterator

try:
    import yaml
except ImportError:
    sys.stderr.write("check-ansible-downloads.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
TREES = ("ansible", "collections/ansible_collections/fleet/debian_guest")
SKIP_PARTS = {"files", "templates"}
SKIP_NAMES = {"vault.yml"}  # ansible-vault ciphertext
GET_URL = {"ansible.builtin.get_url", "get_url"}
REPO_MODULES = {
    "ansible.builtin.deb822_repository",
    "deb822_repository",
    "ansible.builtin.apt_repository",
    "apt_repository",
}
APT_KEY = {"ansible.builtin.apt_key", "apt_key"}
VAR_RE = re.compile(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")


def yaml_files() -> Iterator[Path]:
    for tree in TREES:
        for path in sorted((ROOT / tree).rglob("*.yml")):
            rel = path.relative_to(ROOT)
            if SKIP_PARTS & set(rel.parts) or path.name in SKIP_NAMES:
                continue
            yield path


def load(path: Path) -> list[Any]:
    try:
        return [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]
    except yaml.YAMLError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)}: not valid YAML: {exc}")


def walk(node: Any) -> Iterator[dict]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def defined_vars(docs_by_path: dict[Path, list[Any]]) -> set[str]:
    """Top-level keys of defaults/, group_vars/, host_vars/ and vars files."""
    names: set[str] = set()
    for path, docs in docs_by_path.items():
        parts = set(path.parts)
        if parts & {"defaults", "group_vars", "host_vars", "vars"} or path.name == "all.yml":
            for doc in docs:
                if isinstance(doc, dict):
                    names.update(doc)
    return names


def check_task(task: dict, rel: Path, known: set[str]) -> list[str]:
    problems: list[str] = []
    label = task.get("name", "<unnamed>")
    for module in GET_URL & task.keys():
        args = task[module]
        checksum = args.get("checksum") if isinstance(args, dict) else None
        if not checksum or not str(checksum).strip():
            problems.append(f"{rel}: get_url '{label}' has no checksum")
            continue
        for var in VAR_RE.findall(str(checksum)):
            if var not in known:
                problems.append(
                    f"{rel}: get_url '{label}' checksum uses undefined variable {var}"
                )
    for module in REPO_MODULES & task.keys():
        args = task[module]
        signed_by = args.get("signed_by") if isinstance(args, dict) else None
        if isinstance(signed_by, str) and re.match(r"https?://", signed_by.strip()):
            problems.append(
                f"{rel}: {module} '{label}' signed_by is a URL; pin the key with get_url + checksum"
            )
    for module in APT_KEY & task.keys():
        problems.append(f"{rel}: '{label}' uses apt_key; use get_url + checksum and signed_by")
    return problems


def check_requirements(docs: list[Any], rel: Path) -> list[str]:
    problems: list[str] = []
    for doc in docs:
        for entry in (doc or {}).get("collections", []) if isinstance(doc, dict) else []:
            if isinstance(entry, dict) and not entry.get("version"):
                problems.append(f"{rel}: collection {entry.get('name')} has no version")
            elif isinstance(entry, str):
                problems.append(f"{rel}: collection {entry} has no version")
    return problems


def main() -> int:
    docs_by_path = {path: load(path) for path in yaml_files()}
    known = defined_vars(docs_by_path)
    problems: list[str] = []
    seen_get_url = 0
    for path, docs in docs_by_path.items():
        rel = path.relative_to(ROOT)
        if path.name == "requirements.yml":
            problems += check_requirements(docs, rel)
            continue
        for doc in docs:
            for node in walk(doc):
                seen_get_url += len(GET_URL & node.keys())
                problems += check_task(node, rel, known)
    if seen_get_url == 0:
        problems.append("found zero get_url tasks; the scan is not reading the trees")
    if problems:
        sys.stderr.write("\n".join(sorted(set(problems))) + "\n")
        return 1
    print(f"✓ Ansible downloads are pinned ({seen_get_url} get_url tasks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
