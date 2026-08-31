#!/usr/bin/env bash
# Fill this host (and operator tooling) into Attic from public substituters
# if anything is missing, prove the closure is in Attic, copy it onto the
# target *from Attic only*, then switch. After fill, no cache.nixos.org.
#
# Required: ATTIC_TOKEN
# Optional: ATTIC_COPY_FROM_BUILDER=1 copies from the builder store instead
# (bootstrap hatch for the Attic hosts themselves).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

HOST="${1:-}"
if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi

NIX=$(nix_bin)
require_attic_token

host_system=$("$NIX" eval --raw ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")
if ! nix_can_run_system "$host_system"; then
  echo "ERROR: $HOST is $host_system; this builder is $(current_nix_system)." >&2
  echo "Run aarch64 fill/deploy on the Pi: ./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh $HOST" >&2
  exit 1
fi

ensure_attic_cli
attic_login
attic_push_closure "$ATTIC_CLI_PATH"
attic_fill_tooling

# Prefer the repo pin. OpenSSH keeps the first value for each -o, so these
# must come first: a stale /etc/ssh/ssh_known_hosts on the builder
# (GlobalKnownHostsFile) is what produced "REMOTE HOST IDENTIFICATION HAS
# CHANGED" even with UserKnownHostsFile=/dev/null.
FLEET_KNOWN_HOSTS="$ROOT/ssh/fleet_known_hosts"
NIX_SSHOPTS="-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${FLEET_KNOWN_HOSTS} -o GlobalKnownHostsFile=${FLEET_KNOWN_HOSTS} ${NIX_SSHOPTS:-}"
export NIX_SSHOPTS

echo "========================================="
echo "Deploying $HOST from Attic (fill, then exclusive)"
echo "========================================="

echo "Filling $HOST into Attic..."
out_path=$(attic_fill_installable ".#deploy.nodes.${HOST}.profiles.system.path")

echo "Proving $HOST closure is in Attic..."
if ! attic_closure_cached "$out_path"; then
  echo "ERROR: $HOST closure is not fully in Attic at $ATTIC_CACHE_URL after fill" >&2
  exit 1
fi
if ! nix_realize_attic_only ".#deploy.nodes.${HOST}.profiles.system.path" >/dev/null; then
  echo "ERROR: exclusive realize of $HOST from Attic failed" >&2
  exit 1
fi

local_name=$(hostname -s 2>/dev/null || hostname)
if [ "$local_name" = "$HOST" ]; then
  echo "Target is this host; switching $out_path locally..."
  "$out_path/bin/switch-to-configuration" switch
else
  echo "Copying $out_path from Attic onto root@$HOST..."
  attic_copy_closure_to_ssh "$HOST" "$out_path"

  echo "Switching $HOST to $out_path..."
  # NIX_SSHOPTS is a string of ssh flags (used by nix copy as well).
  # shellcheck disable=SC2086
  ssh ${NIX_SSHOPTS:-} "root@${HOST}" "$out_path/bin/switch-to-configuration" switch
fi

echo "✓ $HOST switched from Attic"
