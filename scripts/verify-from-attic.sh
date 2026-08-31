#!/usr/bin/env bash
# Prove operator tooling and current-system host closures are in Attic
# (narinfo only). Does not download NARs; deploy-from-attic.sh copies them
# onto the target. Fails if any narinfo is missing.
#
# Required: ATTIC_TOKEN (scripts still login; Nix substituter pull is
# tailnet HTTP).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

require_attic_token
NIX=$(nix_bin)
ensure_attic_cli
attic_login

echo "========================================="
echo "Checking tooling and current-system hosts on Attic (narinfo)"
echo "Substituter: $ATTIC_CACHE_URL"
echo "========================================="

failed=0
prove_cached() {
  local attr="$1"
  local evaled
  echo "Checking $attr narinfos on Attic..."
  evaled=$("$NIX" eval --raw "$attr")
  if ! attic_closure_cached "$evaled"; then
    echo "ERROR: $attr is not fully in Attic at $ATTIC_CACHE_URL" >&2
    failed=1
  fi
}

current_system=$(current_nix_system)
prove_cached ".#packages.${current_system}.attic"
prove_cached ".#packages.${current_system}.ci-tools"
prove_cached ".#devShells.${current_system}.default"

hosts=$(nixos_hosts_for_system)
for host in $hosts; do
  prove_cached ".#deploy.nodes.${host}.profiles.system.path"
done

if [ "$failed" -ne 0 ]; then
  echo "========================================="
  echo "verify-from-attic failed"
  echo "========================================="
  exit 1
fi

echo "========================================="
echo "✓ Tooling and $(current_nix_system) host closures present in Attic"
echo "========================================="
