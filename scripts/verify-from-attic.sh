#!/usr/bin/env bash
# Realize operator tooling and current-system host toplevels from Attic only. No
# cache.nixos.org, no local compile (--max-jobs 0, fallback false). Fails if
# any NAR is missing.
#
# Required: ATTIC_TOKEN (scripts still login; Nix substituter pull is
# tailnet HTTP). Optional hatch: none. This is the exclusive-realize gate.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

require_attic_token
NIX=$(nix_bin)

echo "========================================="
echo "Realizing tooling and current-system hosts from Attic only"
echo "Substituter: $ATTIC_CACHE_URL"
echo "========================================="

failed=0
realize() {
  local attr="$1"
  echo "Realizing $attr from Attic..."
  if ! nix_realize_attic_only "$attr" >/dev/null; then
    echo "ERROR: $attr is not fully in Attic at $ATTIC_CACHE_URL" >&2
    failed=1
  fi
}

current_system=$(current_nix_system)
realize ".#packages.${current_system}.attic"
if [ "$failed" -eq 0 ]; then
  attic_cli_path=$(nix_realize_attic_only ".#packages.${current_system}.attic")
  export PATH="${attic_cli_path}/bin:${PATH}"
  attic_login
fi

realize ".#devShells.${current_system}.default"

hosts=$(nixos_hosts_for_system)
for host in $hosts; do
  realize ".#deploy.nodes.${host}.profiles.system.path"
done

if [ "$failed" -ne 0 ]; then
  echo "========================================="
  echo "verify-from-attic failed"
  echo "========================================="
  exit 1
fi

echo "========================================="
echo "✓ Tooling and $(current_nix_system) host toplevels realized from Attic"
echo "========================================="
