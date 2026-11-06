#!/usr/bin/env bash
# Fail if fleet.debian_guest inventory guests are missing from
# fleet.inventory.hosts (MagicDNS / scrape names).
#
# Inventory hostname is usually the MagicDNS name. Exception: the builder
# guest is inventory `proxmox-dev-debian` with MagicDNS `proxmox-dev`
# (debian_guest_tailscale_hostname in host_vars).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

INV="$ROOT/collections/ansible_collections/fleet/debian_guest/inventory/hosts.yml"
if [ ! -f "$INV" ]; then
  echo "missing $INV" >&2
  exit 1
fi

export FLEET_HOSTS_JSON
FLEET_HOSTS_JSON=$(nix eval --json \
  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.hosts')

python3 - "$INV" <<'PY'
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
fleet = set(json.loads(os.environ["FLEET_HOSTS_JSON"]))
inv = yaml.safe_load(inv_path.read_text())
guests = (
    inv.get("all", {})
    .get("children", {})
    .get("debian_guests", {})
    .get("children", {})
    or {}
)
# MagicDNS overrides (must match host_vars debian_guest_tailscale_hostname).
magic = {
    "proxmox-dev-debian": "proxmox-dev",
}
missing = []
checked = []
for _group, body in guests.items():
    for host in body.get("hosts") or {}:
        mdns = magic.get(host, host)
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
