#!/usr/bin/env bash
# Build the x86_64-linux Go bench on proxmox-dev and run it on the Jellyfin host.
# Usage: ./scripts/run-jellyfin-io-bench.sh [dns|transcode|all]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

HOST=${HOST:-proxmox-applications-1}
BUILDER=${BUILDER:-proxmox-dev}
DURATION=${DURATION:-120s}
IDLE=${IDLE:-15s}
SUBCMD=${1:-all}

rsync -az --delete \
  --exclude='.git/' \
  --exclude='result' \
  --exclude='.direnv/' \
  --exclude='.devenv/' \
  --exclude='.idea/' \
  "$ROOT/" "root@${BUILDER}:/root/nixos-fleet-deploy/"

ssh -o BatchMode=yes "root@${BUILDER}" bash -s << EOF
set -euo pipefail
cd /root/nixos-fleet-deploy
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:\$PATH"
# Host nix.conf is Attic-only. This is a fill-style tooling build: public
# substituters are allowed so we do not compile Go's stdenv from source.
# shellcheck source=attic-common.sh
source ./scripts/attic-common.sh
nix build \
  --option substituters "\$BUILDER_SUBSTITUTERS" \
  --option extra-substituters "" \
  --option trusted-substituters "\$BUILDER_SUBSTITUTERS" \
  --option trusted-public-keys "\$BUILDER_TRUSTED_PUBLIC_KEYS" \
  .#packages.x86_64-linux.jellyfin-io-bench \
  -o /tmp/jellyfin-io-bench-result
install -m 0755 /tmp/jellyfin-io-bench-result/bin/jellyfin-io-bench /tmp/jellyfin-io-bench
EOF

scp -o BatchMode=yes -p "root@${BUILDER}:/tmp/jellyfin-io-bench" "root@${HOST}:/root/jellyfin-io-bench.bin"
ssh -o BatchMode=yes "root@${HOST}" bash -s << HOST
set -euo pipefail
chmod 0755 /root/jellyfin-io-bench.bin
# Earlier bash benches used /root/jellyfin-io-bench as a directory.
if [ -d /root/jellyfin-io-bench ]; then
  rm -rf /root/jellyfin-io-bench
fi
/root/jellyfin-io-bench.bin -duration ${DURATION} -idle ${IDLE} -json /root/jellyfin-io-bench.json ${SUBCMD}
HOST
scp -o BatchMode=yes "root@${HOST}:/root/jellyfin-io-bench.json" /tmp/jellyfin-io-bench.json
echo "copied report to /tmp/jellyfin-io-bench.json"
