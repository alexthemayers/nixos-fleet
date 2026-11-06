#!/usr/bin/env bash
# Validate the committed Prometheus alert rules.
#
# Hygiene (duplicate alertname/severity, missing summary/description) runs
# with Python and works on Darwin. PromQL needs promtool (x86_64-linux).
# GitLab CI and make check-obs-config run the full check on proxmox-dev.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

RULES="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml"

if [ ! -f "$RULES" ]; then
  echo "missing $RULES" >&2
  exit 1
fi

echo "Checking rule hygiene..."
python3 "$ROOT/scripts/check-alert-rules.py" "$RULES"

# shellcheck source=scripts/nix-common.sh
source "$ROOT/scripts/nix-common.sh"

echo "Building promtool..."
if ! promtool=$(nix_build_with_builder 'nixpkgs#prometheus.cli')/bin/promtool ||
  [ ! -x "$promtool" ]; then
  echo "" >&2
  echo "Could not build promtool. On Darwin this is expected: the" >&2
  echo "derivation is x86_64-linux. Hygiene passed; run the full check" >&2
  echo "on proxmox-dev for PromQL validation." >&2
  exit 1
fi

echo "Checking $RULES"
"$promtool" check rules "$RULES"
