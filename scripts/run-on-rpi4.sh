#!/usr/bin/env bash
# Sync this checkout onto rpi4 and run a command there. aarch64 deploy
# executes on the Pi (native). It does not run under qemu on proxmox-dev.
#
# Usage: ./scripts/run-on-rpi4.sh ./scripts/deploy-host.sh rpi4
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 1
fi

HOST=rpi4
REMOTE_DIR=/root/nixos-fleet-deploy
FLEET_KNOWN_HOSTS="$ROOT/ssh/fleet_known_hosts"
SSH_OPTS=(
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${FLEET_KNOWN_HOSTS}"
  -o GlobalKnownHostsFile="${FLEET_KNOWN_HOSTS}"
  -o BatchMode=yes
  -o ConnectTimeout=8
)

if ! ssh "${SSH_OPTS[@]}" "root@${HOST}" true; then
  echo "ERROR: ${HOST} is unreachable; aarch64 deploy cannot run on this builder" >&2
  exit 1
fi

ssh "${SSH_OPTS[@]}" "root@${HOST}" "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
# tar so the Pi does not need rsync on the first native deploy.
COPYFILE_DISABLE=1 tar -C "$ROOT" \
  --exclude='.git' \
  --exclude='result' \
  --exclude='.direnv' \
  --exclude='.devenv' \
  -cf - . \
  | ssh "${SSH_OPTS[@]}" "root@${HOST}" "tar -C ${REMOTE_DIR} -xf -"

remote_script=$(mktemp)
trap 'rm -f "$remote_script"' EXIT
{
  echo 'set -euo pipefail'
  echo "cd ${REMOTE_DIR}"
  echo 'export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"'
  if [ -n "${FORCE_SWITCH:-}" ]; then
    printf 'export FORCE_SWITCH=%q\n' "$FORCE_SWITCH"
  fi
  printf 'exec '
  printf '%q ' "$@"
  echo
} >"$remote_script"

ssh "${SSH_OPTS[@]}" "root@${HOST}" 'bash -s' <"$remote_script"
