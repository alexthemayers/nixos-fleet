#!/usr/bin/env bash
# Fill Attic: realize with public substituters if a path is missing, then
# attic push. Does not activate hosts. After this, verify-from-attic.sh checks
# narinfos and deploy-from-attic.sh copies exclusively from Attic.
#
# Required: ATTIC_TOKEN
# Optional: ATTIC_SKIP_IF_CACHED=1, ATTIC_TOOLING_ONLY=1, ATTIC_PUSH_JOBS=8,
#   ATTIC_FILL_PUBLIC_ONLY=1 (empty Garage / ghost narinfos)
# Fill only currentSystem hosts. aarch64 (rpi4) is filled on the Pi:
#   ./scripts/run-on-rpi4.sh ./scripts/build.sh
# Concurrent pushes need Garage on LMDB. A node still on sqlite must stay at
# ATTIC_PUSH_JOBS=1: docs/runbooks/garage-lmdb.md.
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

attic_fill_hosts

echo ""
echo "========================================="
echo "✓ Closures filled into Attic"
echo "========================================="
