#!/bin/bash
# One TCP connect attempt per second, bounded. Not a tight loop.
set -euo pipefail
host=$1
port=$2
deadline=$((SECONDS + 90))
while ((SECONDS < deadline)); do
  if timeout 2 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
    exit 0
  fi
  sleep 1
done
echo "timed out waiting for ${host}:${port}" >&2
exit 1
