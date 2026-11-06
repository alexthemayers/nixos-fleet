#!/usr/bin/env python3
"""Fail when an Ansible task passes an argument its module does not accept.

ansible-lint --offline and --syntax-check do not validate module arguments,
and a `--check` run skips the module's own validation. `ansible.builtin.copy`
with `delete: true` (a `synchronize` option) therefore passed CI and failed
the first real deploy.

For every task under ansible/ and the debian_guest collection this reads the
module's options (and aliases) from `ansible-doc` and rejects keys the module
does not define. Run it with ANSIBLE_COLLECTIONS_PATH pointing at the Galaxy
collections from requirements.yml (scripts/ansible-lint.sh does).

Not checked: free-form modules (set_fact, include_tasks, ...), tasks whose
args are a string, keys that contain a template, and non-FQCN module names.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterator

try:
    import yaml
except ImportError:
    sys.stderr.write("check-ansible-module-args.py needs PyYAML (python3-yaml)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
TREES = ("ansible", "collections/ansible_collections/fleet/debian_guest")
SKIP_PARTS = {"files", "templates", "defaults", "vars", "group_vars", "host_vars", "meta"}
SKIP_NAMES = {"vault.yml", "requirements.yml", "galaxy.yml", "hosts.yml"}
# Arbitrary key=value or per-task variables rather than a fixed option set.
FREE_FORM = {
    "ansible.builtin.set_fact",
    "ansible.builtin.set_stats",
    "ansible.builtin.add_host",
    "ansible.builtin.group_by",
    "ansible.builtin.include_tasks",
    "ansible.builtin.import_tasks",
    "ansible.builtin.include_role",
    "ansible.builtin.import_role",
    "ansible.builtin.include_vars",
    "ansible.builtin.import_playbook",
    "ansible.builtin.meta",
}
BLOCK_KEYS = ("block", "rescue", "always")
PLAY_TASK_KEYS = ("tasks", "pre_tasks", "post_tasks", "handlers")


def keywords() -> set[str]:
    out = subprocess.run(
        ["ansible-doc", "-t", "keyword", "-l", "-j"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return set(json.loads(out))


def yaml_files() -> Iterator[Path]:
    for tree in TREES:
        for path in sorted((ROOT / tree).rglob("*.yml")):
            rel = path.relative_to(ROOT)
            if SKIP_PARTS & set(rel.parts) or path.name in SKIP_NAMES:
                continue
            yield path


def iter_tasks(node: Any) -> Iterator[dict]:
    """Yield every task dict in a tasks file, handlers file or playbook."""
    if isinstance(node, list):
        for item in node:
            yield from iter_tasks(item)
    elif isinstance(node, dict):
        if "hosts" in node:
            for key in PLAY_TASK_KEYS:
                yield from iter_tasks(node.get(key) or [])
            return
        yield node
        for key in BLOCK_KEYS:
            yield from iter_tasks(node.get(key) or [])


def module_of(task: dict, kws: set[str]) -> str | None:
    for key in task:
        if key in kws or key.startswith("with_") or key in {"action", "local_action"}:
            continue
        return key
    return None


def task_modules(tasks: list[tuple[Path, dict]], kws: set[str]) -> set[str]:
    found = set()
    for _, task in tasks:
        module = module_of(task, kws)
        if module and "." in module and module not in FREE_FORM:
            found.add(module)
    return found


def module_options(modules: set[str]) -> dict[str, set[str]]:
    """FQCN -> accepted argument names (options plus aliases)."""
    if not modules:
        return {}
    proc = subprocess.run(
        ["ansible-doc", "-t", "module", "-j", *sorted(modules)],
        capture_output=True,
        text=True,
    )
    docs = json.loads(proc.stdout) if proc.stdout.strip() else {}
    accepted: dict[str, set[str]] = {}
    for fqcn, entry in docs.items():
        names: set[str] = set()
        for name, spec in (entry.get("doc", {}).get("options") or {}).items():
            names.add(name)
            names.update(spec.get("aliases") or [])
        accepted[fqcn] = names
    return accepted


def check_task(task: dict, rel: Path, kws: set[str], accepted: dict[str, set[str]]) -> list[str]:
    module = module_of(task, kws)
    if not module or "." not in module or module in FREE_FORM:
        return []
    args = task[module]
    if not isinstance(args, dict):
        return []
    label = task.get("name", "<unnamed>")
    if module not in accepted:
        return [f"{rel}: '{label}': ansible-doc does not know module {module}"]
    unknown = sorted(k for k in args if "{{" not in str(k) and k not in accepted[module])
    return [
        f"{rel}: '{label}': {module} has no option '{key}'"
        for key in unknown
    ]


def main() -> int:
    kws = keywords()
    tasks: list[tuple[Path, dict]] = []
    for path in yaml_files():
        try:
            docs = [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]
        except yaml.YAMLError as exc:
            sys.stderr.write(f"{path.relative_to(ROOT)}: not valid YAML: {exc}\n")
            return 1
        rel = path.relative_to(ROOT)
        for doc in docs:
            tasks.extend((rel, t) for t in iter_tasks(doc))

    accepted = module_options(task_modules(tasks, kws))
    problems: list[str] = []
    checked = 0
    for rel, task in tasks:
        module = module_of(task, kws)
        if module in accepted:
            checked += 1
        problems += check_task(task, rel, kws, accepted)
    if checked == 0:
        problems.append("checked zero tasks; ansible-doc or the scan is not working")
    if problems:
        sys.stderr.write("\n".join(sorted(set(problems))) + "\n")
        return 1
    print(f"✓ Ansible module arguments are valid ({checked} tasks, {len(accepted)} modules)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
