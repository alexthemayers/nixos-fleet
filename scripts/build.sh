#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting Sequential Flake Builds"
echo "========================================="

echo "Retrieving list of host configurations for the current architecture..."
current_system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
hosts=$(nix eval --raw .#nixosConfigurations --apply "x: let inherit (builtins) attrNames filter concatStringsSep; hostsForSystem = filter (name: x.\${name}.pkgs.stdenv.hostPlatform.system == \"$current_system\") (attrNames x); in concatStringsSep \" \" hostsForSystem")

for host in $hosts; do
  echo "Building host: $host..."
  out_path=$(nix build .#deploy.nodes."$host".profiles.system.path --print-out-paths --no-link -L)
  
  if [ -n "${ATTIC_TOKEN:-}" ]; then
    echo "Pushing $host closure to Attic cache..."
    # Push the closure and all its dependencies
    attic push attic "$out_path"
  fi
done

echo ""
echo "========================================="
echo "✓ All configurations built successfully!"
echo "========================================="
