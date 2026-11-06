#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting flake lint checks"
echo "========================================="

# --all-systems evaluates x86_64 and aarch64 deploy-rs schema.
# Per-host drvPath loops were redundant with this.
echo "Running nix flake check --all-systems --no-build..."
nix flake check --all-systems --no-build --show-trace
echo "✓ Flake checks passed"
echo ""


echo "Checking alert rule hygiene..."
nix-shell -p python3Packages.pyyaml --run \
  "python3 scripts/check-alert-rules.py collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml"
echo "✓ Alert rule hygiene passed"
echo ""

echo "========================================="
echo "✓ All configuration lint checks passed!"
echo "========================================="
