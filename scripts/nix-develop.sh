#!/usr/bin/env bash
# Enter the flake devShell. With ATTIC_TOKEN, fill the shell into Attic
# first (public substituters if missing), then `nix develop` with Attic
# only. Without a token (laptop lint), pass through to nix develop.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

NIX=$(nix_bin)
load_attic_token

if [ -z "${ATTIC_TOKEN:-}" ]; then
  exec "$NIX" develop "$@"
fi

ensure_attic_cli
attic_login
attic_push_closure "$ATTIC_CLI_PATH"
ATTIC_SKIP_IF_CACHED="${ATTIC_SKIP_IF_CACHED:-1}" attic_fill_tooling

exec "$NIX" develop \
  --option substituters "$ATTIC_CACHE_URL" \
  --option extra-substituters "" \
  --option trusted-substituters "$ATTIC_CACHE_URL" \
  --option trusted-public-keys "$ATTIC_PUBLIC_KEY" \
  --option fallback false \
  --option narinfo-cache-negative-ttl 0 \
  "$@"
