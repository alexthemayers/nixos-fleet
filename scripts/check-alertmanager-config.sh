#!/usr/bin/env bash
# Validate the committed Alertmanager config with amtool.
#
# Prefer amtool from PATH (flake packages.ci-tools in CI). Fall back to
# nix_build_with_builder only outside CI.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

CONFIG="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/alertmanager.yml"

if [ ! -f "$CONFIG" ]; then
  echo "missing $CONFIG" >&2
  exit 1
fi

resolve_amtool() {
  if command -v amtool >/dev/null 2>&1; then
    command -v amtool
    return 0
  fi
  # shellcheck source=scripts/nix-common.sh
  source "$ROOT/scripts/nix-common.sh"
  local out
  out=$(nix_build_with_builder 'nixpkgs#prometheus-alertmanager') || return 1
  printf '%s' "$out/bin/amtool"
}

echo "Resolving amtool..."
if ! amtool=$(resolve_amtool) || [ ! -x "$amtool" ]; then
  echo "amtool not on PATH and nix build failed. In CI, realize .#ci-tools." >&2
  exit 1
fi

echo "Checking $CONFIG"
"$amtool" check-config "$CONFIG"
echo "✓ Alertmanager config ok"
