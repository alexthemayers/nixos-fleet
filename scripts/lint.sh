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

# Evaluating drvPath only proves the derivation can be computed. It does not run
# the deploy-rs schema checks as builds, so a node whose activation script or
# schema is wrong still passed lint and went straight to production, because CI
# also deployed with --skip-checks. Both of those are now closed.
echo "Building flake checks (deploy-rs activation and schema)..."
nix flake check --no-build --show-trace
echo "✓ Flake checks passed"
echo ""

echo "========================================="
echo "✓ All configuration lint checks passed!"
echo "========================================="
