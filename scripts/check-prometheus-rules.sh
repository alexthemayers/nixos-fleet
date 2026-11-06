#!/usr/bin/env bash
# Validate the committed Prometheus alert rules.
#
# Hygiene needs PyYAML. PromQL needs promtool. Prefer binaries from PATH
# (flake packages.ci-tools in CI) so we do not resolve unpinned nixpkgs#
# registry flakes. Fall back to nix_build_with_builder only outside CI.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

RULES="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml"

if [ ! -f "$RULES" ]; then
  echo "missing $RULES" >&2
  exit 1
fi

echo "Checking rule hygiene..."
if ! python3 "$ROOT/scripts/check-alert-rules.py" "$RULES"; then
  # Local Darwin without PyYAML: match lint.sh.
  if command -v nix-shell >/dev/null 2>&1; then
    nix-shell -p python3Packages.pyyaml --run \
      "python3 '$ROOT/scripts/check-alert-rules.py' '$RULES'"
  else
    exit 1
  fi
fi

resolve_promtool() {
  if command -v promtool >/dev/null 2>&1; then
    command -v promtool
    return 0
  fi
  # shellcheck source=scripts/nix-common.sh
  source "$ROOT/scripts/nix-common.sh"
  local out
  out=$(nix_build_with_builder 'nixpkgs#prometheus.cli') || return 1
  printf '%s' "$out/bin/promtool"
}

echo "Resolving promtool..."
if ! promtool=$(resolve_promtool) || [ ! -x "$promtool" ]; then
  echo "promtool not on PATH and nix build failed. In CI, realize .#ci-tools." >&2
  exit 1
fi

echo "Checking $RULES"
"$promtool" check rules "$RULES"
echo "✓ promtool check rules ok"
