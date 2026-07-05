#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting Sequential Flake Lint Checks"
echo "========================================="

echo "Evaluating deploy-rs configuration schemas..."
nix eval .#checks.x86_64-linux.deploy-schema.drvPath --show-trace
nix eval .#checks.aarch64-linux.deploy-schema.drvPath --show-trace
echo "✓ Schema checks evaluated successfully"
echo ""

echo "Retrieving list of host configurations..."
hosts=$(nix eval --raw .#nixosConfigurations --apply "x: builtins.concatStringsSep \" \" (builtins.attrNames x)")

for host in $hosts; do
  echo "Evaluating host: $host..."
  nix eval .#deploy.nodes."$host".profiles.system.path.drvPath --show-trace
done

echo ""
echo "========================================="
echo "✓ All configuration lint checks passed!"
echo "========================================="
