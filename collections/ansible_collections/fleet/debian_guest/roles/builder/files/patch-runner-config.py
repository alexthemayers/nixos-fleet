#!/usr/bin/env python3
"""Set the CI container caps in an existing config.toml."""

import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
wanted = {
    "memory": '"12g"',
    "memory_swap": '"12g"',
    "cpus": '"3"',
    "privileged": "false",
    "host": '"unix:///run/gitlab-runner/podman.sock"',
}

start = text.find("[runners.docker]")
if start < 0:
    sys.stderr.write("config.toml has no [runners.docker] section\n")
    sys.exit(1)
rest = text[start + len("[runners.docker]") :]
end = rest.find("\n[")
section = rest[:end] if end >= 0 else rest
tail = rest[end:] if end >= 0 else ""
lines = section.splitlines()
keys_present = set()
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue
    keys_present.add(stripped.split("=", 1)[0].strip())
for key, value in wanted.items():
    if key not in keys_present:
        lines.append(f"    {key} = {value}")
new_section = "\n".join(lines)
path.write_text(text[:start] + "[runners.docker]" + new_section + tail)
