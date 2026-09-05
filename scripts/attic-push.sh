#!/usr/bin/env bash
# Push one store path (and its closure) to Attic.
# Usage: ATTIC_TOKEN=… ./scripts/attic-push.sh /nix/store/…-something
#
# Required: ATTIC_TOKEN. Concurrent pushes need Garage on LMDB (deploy db-1
# and db-2 first: docs/runbooks/garage-lmdb.md).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

out_path="${1:-}"
if [ -z "$out_path" ]; then
  echo "Usage: $0 <store-path>" >&2
  exit 1
fi

require_attic_token
attic_login
NIX=$(nix_bin)
attic_push_closure "$out_path"
