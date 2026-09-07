#!/usr/bin/env bash
# Validate the generated Mimir rules with promtool.
#
# services/mimir-rules.nix asserts rule hygiene at eval time (duplicate
# alertnames, missing annotations, missing `for`), because `make lint` and CI
# both run `nix flake check --no-build` and would never build a derivation.
# What those assertions cannot do is parse PromQL or expand an annotation
# template, which is the failure that reaches the ruler as
# `cortex_ruler_config_last_reload_successful 0` and leaves the fleet on stale
# rules.
#
# The rules file is an x86_64-linux derivation, so this needs a Linux builder:
# run it on proxmox-dev, not the Darwin checkout.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck source=scripts/attic-common.sh
source "$ROOT/scripts/attic-common.sh"

host=proxmox-observability-1
attr=".#nixosConfigurations.${host}.config.environment.etc.\"mimir-rules/anonymous/rules.yaml\".source"

echo "Building the rules file for ${host}..."
if ! rules=$(nix_build_with_builder "$attr" 2>&1 | tail -1) ||
  [ ! -e "$rules" ]; then
  echo "" >&2
  echo "Could not build the rules file. On Darwin this is expected: the" >&2
  echo "derivation is x86_64-linux. Run this on proxmox-dev." >&2
  exit 1
fi

promtool=$(nix_build_with_builder 'nixpkgs#prometheus.cli')/bin/promtool

echo "Checking $rules"
"$promtool" check rules "$rules"
