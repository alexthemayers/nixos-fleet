#!/usr/bin/env bash
# Fail if committed Jellyfin XML under the apps role is not well-formed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/apps/files/jellyfin"

if [ ! -d "$DIR" ]; then
  echo "missing $DIR" >&2
  exit 1
fi

python3 - "$DIR" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
files = sorted(root.rglob("*.xml"))
if not files:
    sys.stderr.write(f"no XML under {root}\n")
    sys.exit(1)
failed = 0
for path in files:
    try:
        ET.parse(path)
    except ET.ParseError as e:
        failed = 1
        sys.stderr.write(f"{path}: {e}\n")
if failed:
    sys.exit(1)
print(f"✓ Jellyfin XML well-formed ({len(files)} files)")
PY
