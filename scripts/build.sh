#!/usr/bin/env bash
# Fill Attic: realize with public substituters if a path is missing, then
# attic push. Does not activate hosts. After this, verify-from-attic.sh and
# deploy-from-attic.sh realize exclusively from Attic.
#
# Required: ATTIC_TOKEN
# Optional: ATTIC_SKIP_IF_CACHED=1, ATTIC_TOOLING_ONLY=1, ATTIC_PUSH_JOBS=8
# Fill only currentSystem hosts. aarch64 (rpi4) is filled on the Pi:
#   ./scripts/run-on-rpi4.sh ./scripts/build.sh
# Deploy proxmox-db-1 and proxmox-db-2 (Garage LMDB) before the first parallel
# fill; sqlite with fsync off will not survive ATTIC_PUSH_JOBS>1.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

NIX=$(nix_bin)
require_attic_token
ensure_attic_cli
attic_login
attic_push_closure "$ATTIC_CLI_PATH"

echo "========================================="
echo "Filling Attic (public substituters only if missing)"
echo "========================================="

attic_fill_tooling

if [ "${ATTIC_TOOLING_ONLY:-}" = 1 ]; then
  echo ""
  echo "========================================="
  echo "✓ Operator tooling filled (ATTIC_TOOLING_ONLY=1)"
  echo "========================================="
  exit 0
fi

echo "Retrieving list of host configurations for $(current_nix_system)..."
if [ "${ATTIC_BUILD_ALL_SYSTEMS:-}" = 1 ]; then
  echo "ATTIC_BUILD_ALL_SYSTEMS=1 no longer fills foreign architectures; aarch64 runs on rpi4." >&2
fi
hosts=$(nixos_hosts_for_system)

for host in $hosts; do
  out_path=$(attic_fill_installable ".#deploy.nodes.${host}.profiles.system.path")

  # Drop the toplevel from the builder store after a successful push. Do not
  # nix-collect-garbage -d here: this script also runs on workstations.
  "$NIX" store delete "$out_path" || true
done

echo ""
echo "========================================="
echo "✓ Closures filled into Attic"
echo "========================================="
