#!/usr/bin/env bash
# Fill this host (and operator tooling) into Attic from public substituters
# if anything is missing, prove the closure is in Attic, copy it onto the
# target *from Attic only*, then switch. After fill, no cache.nixos.org.
#
# Required: ATTIC_TOKEN
# Optional:
#   ATTIC_COPY_FROM_BUILDER=1  copy from the builder store (bootstrap hatch)
#   ATTIC_SKIP_FILL=1          do not fill; CI after verify-from-attic
#   ATTIC_FORCE_SWITCH=1       switch even if /run/current-system matches
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

# Prefer the repo pin. OpenSSH keeps the first value for each -o, so these
# must come first: a stale /etc/ssh/ssh_known_hosts on the builder
# (GlobalKnownHostsFile) is what produced "REMOTE HOST IDENTIFICATION HAS
# CHANGED" even with UserKnownHostsFile=/dev/null.
FLEET_KNOWN_HOSTS="$ROOT/ssh/fleet_known_hosts"
NIX_SSHOPTS="-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${FLEET_KNOWN_HOSTS} -o GlobalKnownHostsFile=${FLEET_KNOWN_HOSTS} ${NIX_SSHOPTS:-}"
export NIX_SSHOPTS

local_name=$(hostname -s 2>/dev/null || hostname)

read_current_system() {
  if [ "$local_name" = "$HOST" ]; then
    readlink /run/current-system
  else
    # NIX_SSHOPTS is a string of ssh flags (used by nix copy as well).
    # shellcheck disable=SC2086
    ssh ${NIX_SSHOPTS:-} "root@${HOST}" readlink /run/current-system
  fi
}

# deploy-rs activate.nixos is a buildEnv wrapping the toplevel; the running
# system is the toplevel. Compare that, not the activatable path.
toplevel=$("$NIX" eval --raw ".#nixosConfigurations.${HOST}.config.system.build.toplevel")

if [ "${ATTIC_FORCE_SWITCH:-}" != 1 ]; then
  current=$(read_current_system || true)
  if [ -n "${current:-}" ] && [ "$current" = "$toplevel" ]; then
    echo "Skipping $HOST (already running $toplevel)"
    exit 0
  fi
fi

ensure_attic_cli
attic_login

echo "========================================="
echo "Deploying $HOST from Attic"
echo "========================================="

if [ "${ATTIC_SKIP_FILL:-}" = 1 ]; then
  out_path=$("$NIX" eval --raw ".#deploy.nodes.${HOST}.profiles.system.path")
  echo "ATTIC_SKIP_FILL=1; using $out_path"
else
  attic_push_closure "$ATTIC_CLI_PATH"
  if [ "${ATTIC_SKIP_TOOLING:-}" = 1 ]; then
    echo "ATTIC_SKIP_TOOLING=1; not filling attic CLI / ci-tools / devShell"
  else
    attic_fill_tooling
  fi
  echo "Filling $HOST into Attic..."
  out_path=$(attic_fill_installable ".#deploy.nodes.${HOST}.profiles.system.path")
fi

echo "Proving $HOST closure is in Attic..."
if ! attic_closure_cached "$out_path"; then
  echo "ERROR: $HOST closure is not fully in Attic at $ATTIC_CACHE_URL" >&2
  exit 1
fi

if [ "${ATTIC_SKIP_FILL:-}" != 1 ]; then
  if ! nix_realize_attic_only ".#deploy.nodes.${HOST}.profiles.system.path" >/dev/null; then
    echo "ERROR: exclusive realize of $HOST from Attic failed" >&2
    exit 1
  fi
fi

if [ "$local_name" = "$HOST" ]; then
  # Local switch needs the path in this store. Remote copy pulls from Attic
  # onto the target and does not.
  if [ "${ATTIC_SKIP_FILL:-}" = 1 ]; then
    if ! nix_realize_attic_only ".#deploy.nodes.${HOST}.profiles.system.path" >/dev/null; then
      echo "ERROR: exclusive realize of $HOST from Attic failed" >&2
      exit 1
    fi
  fi
  echo "Target is this host; switching $out_path locally..."
  "$out_path/bin/switch-to-configuration" switch
else
  echo "Copying $out_path from Attic onto root@$HOST..."
  attic_copy_closure_to_ssh "$HOST" "$out_path"

  echo "Switching $HOST to $out_path..."
  # shellcheck disable=SC2086
  ssh ${NIX_SSHOPTS:-} "root@${HOST}" "$out_path/bin/switch-to-configuration" switch
fi

echo "✓ $HOST switched from Attic"
