#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting Sequential Flake Builds"
echo "========================================="

echo "Retrieving list of host configurations..."
hosts=$(nix eval --raw .#nixosConfigurations --apply "x: builtins.concatStringsSep \" \" (builtins.attrNames x)")

for host in $hosts; do
  echo "Building host: $host..."
  nix build .#nixosConfigurations."$host".config.system.build.toplevel --no-link -L
done

echo ""
echo "========================================="
echo "✓ All configurations built successfully!"
echo "========================================="
