#!/usr/bin/env bash
# Build this host on a native builder and activate it with deploy-rs.
# The closure is copied from the builder store (fastConnection = true).
# CLI substituters are the public caches, so the first switch still works
# while the running nix.conf points at Attic.
#
# Optional:
#   FORCE_SWITCH=1    switch even if /run/current-system matches the toplevel
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=nix-common.sh
source "$ROOT/scripts/nix-common.sh"

HOST="${1:-}"
if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi

NIX=$(nix_bin)
use_builder_cache
# Child nix commands (deploy-rs runs its own nix) do not see the --option
# flags on the outer `nix develop`. The running daemon nix.conf is still
# Attic-only until this host is switched. NIX_CONFIG is the client config
# for every nix in this process. max-jobs = 1 matches the 12 GiB builder.
export NIX_CONFIG="substituters = ${BUILDER_SUBSTITUTERS}
trusted-public-keys = ${BUILDER_TRUSTED_PUBLIC_KEYS}
extra-substituters =
extra-trusted-public-keys =
max-jobs = 1
narinfo-cache-negative-ttl = 0"

paused=$(nix_eval_with_builder --raw \
  ".#nixosConfigurations.xcloud-caddy.config.fleet.inventory.deployPausedHosts" \
  --apply 'builtins.concatStringsSep " "')
case " ${paused} " in
  *" ${HOST} "*)
    echo "ERROR: $HOST is in fleet.inventory.deployPausedHosts and must not be activated" >&2
    exit 1
    ;;
esac

host_system=$(nix_eval_with_builder --raw ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")
if ! nix_can_run_system "$host_system"; then
  echo "ERROR: $HOST is $host_system; this builder is $(current_nix_system)." >&2
  echo "Run aarch64 deploy on the Pi: ./scripts/run-on-rpi4.sh ./scripts/deploy-host.sh $HOST" >&2
  exit 1
fi

# Prefer the repo pin. OpenSSH keeps the first value for each -o, so these
# must come first: a stale /etc/ssh/ssh_known_hosts on the builder
# (GlobalKnownHostsFile) is what produced "REMOTE HOST IDENTIFICATION HAS
# CHANGED" even with UserKnownHostsFile=/dev/null.
FLEET_KNOWN_HOSTS="$ROOT/ssh/fleet_known_hosts"
# CLI --ssh-opts replaces flake sshOpts, so repeat ControlMaster here.
# UserKnownHostsFile must be first: OpenSSH keeps the first value.
NIX_SSHOPTS="-o UserKnownHostsFile=${FLEET_KNOWN_HOSTS} -o GlobalKnownHostsFile=${FLEET_KNOWN_HOSTS} -o StrictHostKeyChecking=yes ${NIX_SSHOPTS:-}"
export NIX_SSHOPTS
SSH_OPTS="-o UserKnownHostsFile=${FLEET_KNOWN_HOSTS} -o GlobalKnownHostsFile=${FLEET_KNOWN_HOSTS} -o StrictHostKeyChecking=yes -o ControlMaster=auto -o ControlPath=~/.ssh/deploy-%C -o ControlPersist=10m"

# Short name of this machine. GitLab's nixos/nix + ci-tools image has
# coreutils `uname` but no hostname(1); empty/mismatch means SSH to $HOST.
local_name=$(uname -n 2>/dev/null || true)
local_name=${local_name%%.*}

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
toplevel=$(nix_eval_with_builder --raw ".#nixosConfigurations.${HOST}.config.system.build.toplevel")

if [ "${FORCE_SWITCH:-}" != 1 ]; then
  current=$(read_current_system || true)
  if [ -n "${current:-}" ] && [ "$current" = "$toplevel" ]; then
    echo "Skipping $HOST (already running $toplevel)"
    exit 0
  fi
fi

echo "========================================="
echo "Deploying $HOST with deploy-rs"
echo "========================================="

# --skip-checks: deploy-rs otherwise runs `nix flake check`, which builds
# every check and was SIGKILL'd on this 12 GiB builder. `make lint` is
# the --no-build eval. --confirm-timeout 300: the default 30s is shorter
# than a switch that stops atticd or Postgres, and deploy-rs then rolls back.
exec "$NIX" develop \
  --option substituters "$BUILDER_SUBSTITUTERS" \
  --option extra-substituters "" \
  --option trusted-substituters "$BUILDER_SUBSTITUTERS" \
  --option trusted-public-keys "$BUILDER_TRUSTED_PUBLIC_KEYS" \
  --option max-jobs 1 \
  --option narinfo-cache-negative-ttl 0 \
  -c deploy \
  --skip-checks \
  --confirm-timeout 300 \
  --targets ".#${HOST}" \
  --debug-logs \
  --ssh-opts "$SSH_OPTS"
