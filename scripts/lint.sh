#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting flake lint checks"
echo "========================================="

# --all-systems evaluates x86_64 and aarch64 deploy-rs schema plus
# co-routed-peers. Per-host drvPath loops were redundant with this.
echo "Running nix flake check --all-systems --no-build..."
nix flake check --all-systems --no-build --show-trace
echo "✓ Flake checks passed"
echo ""

echo "========================================="
echo "✓ All configuration lint checks passed!"
echo "========================================="
