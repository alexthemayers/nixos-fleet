#!/usr/bin/env bash
# Validate the committed Alertmanager config with amtool.
#
# amtool is x86_64-linux (same as promtool). Run on proxmox-dev / in CI.
# Darwin may fail the nix build; that is expected — CI still gates merges.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

CONFIG="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/alertmanager.yml"

if [ ! -f "$CONFIG" ]; then
  echo "missing $CONFIG" >&2
  exit 1
fi

# shellcheck source=scripts/nix-common.sh
source "$ROOT/scripts/nix-common.sh"

echo "Building amtool..."
if ! amtool=$(nix_build_with_builder 'nixpkgs#alertmanager')/bin/amtool ||
  [ ! -x "$amtool" ]; then
  echo "" >&2
  echo "Could not build amtool. On Darwin this is expected: the" >&2
  echo "derivation is x86_64-linux. Run make check-obs-config on" >&2
  echo "proxmox-dev or in CI." >&2
  exit 1
fi

echo "Checking $CONFIG"
"$amtool" check-config "$CONFIG"
echo "✓ Alertmanager config ok"
