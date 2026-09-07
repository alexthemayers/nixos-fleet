#!/usr/bin/env bash
# Sync this checkout onto rpi4 and run a command there. aarch64 fill, verify,
# and deploy execute on the Pi (native). They do not run under qemu on
# proxmox-dev. Never print ATTIC_TOKEN.
#
# Usage: ./scripts/run-on-rpi4.sh ./scripts/build.sh
#        ./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh rpi4
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
  echo "ERROR: ${HOST} is unreachable; aarch64 fill/deploy cannot run on this builder" >&2
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
  if [ -n "${ATTIC_TOKEN:-}" ]; then
    printf 'export ATTIC_TOKEN=%q\n' "$ATTIC_TOKEN"
  fi
  for v in ATTIC_SKIP_IF_CACHED ATTIC_TOOLING_ONLY ATTIC_SKIP_TOOLING ATTIC_SKIP_FILL ATTIC_FORCE_SWITCH ATTIC_PUSH_JOBS ATTIC_PUSH_BATCH_SIZE ATTIC_CACHE_URL ATTIC_ENDPOINT ATTIC_COPY_FROM_BUILDER ATTIC_FILL_PUBLIC_ONLY; do
    if [ -n "${!v:-}" ]; then
      printf 'export %s=%q\n' "$v" "${!v}"
    fi
  done
  printf 'exec '
  printf '%q ' "$@"
  echo
} >"$remote_script"

ssh "${SSH_OPTS[@]}" "root@${HOST}" 'bash -s' <"$remote_script"
