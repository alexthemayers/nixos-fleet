#!/usr/bin/env bash
# Enter the flake devShell with public substituters on the CLI, so a
# builder whose running nix.conf still lists Attic can build the shell.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=nix-common.sh
source "$ROOT/scripts/nix-common.sh"

NIX=$(nix_bin)
use_builder_cache

exec "$NIX" develop \
  --option substituters "$BUILDER_SUBSTITUTERS" \
  --option extra-substituters "" \
  --option trusted-substituters "$BUILDER_SUBSTITUTERS" \
  --option trusted-public-keys "$BUILDER_TRUSTED_PUBLIC_KEYS" \
  --option narinfo-cache-negative-ttl 0 \
  "$@"
