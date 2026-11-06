#!/usr/bin/env bash
# Fail if fleet.debian_guest inventory guests are missing from
# fleet.inventory.hosts (MagicDNS / scrape names).
#
# Inventory hostname is usually the MagicDNS name. When host_vars sets
# debian_guest_tailscale_hostname, that value is the MagicDNS name (e.g.
# proxmox-dev-debian → proxmox-dev).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

INV="$ROOT/collections/ansible_collections/fleet/debian_guest/inventory/hosts.yml"
HOST_VARS="$ROOT/collections/ansible_collections/fleet/debian_guest/inventory/host_vars"
if [ ! -f "$INV" ]; then
  echo "missing $INV" >&2
  exit 1
fi

export FLEET_HOSTS_JSON
FLEET_HOSTS_JSON=$(nix eval --json \
  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.hosts')

python3 - "$INV" "$HOST_VARS" <<'PY'
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("check-debian-inventory.sh needs PyYAML\n")
    sys.exit(2)

inv_path = Path(sys.argv[1])
host_vars_dir = Path(sys.argv[2])
fleet = set(json.loads(os.environ["FLEET_HOSTS_JSON"]))
inv = yaml.safe_load(inv_path.read_text())
guests = (
    inv.get("all", {})
    .get("children", {})
    .get("debian_guests", {})
    .get("children", {})
    or {}
)

def magicdns(host: str) -> str:
    hv = host_vars_dir / f"{host}.yml"
    if hv.is_file():
        data = yaml.safe_load(hv.read_text()) or {}
        override = data.get("debian_guest_tailscale_hostname")
        if isinstance(override, str) and override.strip():
            return override.strip()
    return host

missing = []
checked = []
for _group, body in guests.items():
    for host in body.get("hosts") or {}:
        mdns = magicdns(host)
        checked.append((host, mdns))
        if mdns not in fleet:
            missing.append((host, mdns))

if missing:
    for host, mdns in missing:
        sys.stderr.write(
            f"Ansible guest '{host}' (MagicDNS '{mdns}') "
            f"is not in fleet.inventory.hosts\n"
        )
    sys.exit(1)

print(
    f"✓ Debian guest inventory ⊆ fleet.inventory.hosts "
    f"({len(checked)} guests)"
)
PY
