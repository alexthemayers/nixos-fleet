#!/usr/bin/env bash
# Build the x86_64-linux Go bench on proxmox-dev and run it on the Jellyfin host.
# Usage: ./scripts/run-jellyfin-io-bench.sh [dns|probe|transcode|directplay|all]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

HOST=${HOST:-proxmox-applications-debian}
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
# Pass public substituters on the CLI. A running nix.conf may still
# list the removed Attic URL until proxmox-dev is switched.
# shellcheck source=nix-common.sh
source ./scripts/nix-common.sh
use_builder_cache
nix build \
  --option substituters "\$BUILDER_SUBSTITUTERS" \
  --option extra-substituters "" \
  --option trusted-substituters "\$BUILDER_SUBSTITUTERS" \
  --option trusted-public-keys "\$BUILDER_TRUSTED_PUBLIC_KEYS" \
  --option narinfo-cache-negative-ttl 0 \
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
