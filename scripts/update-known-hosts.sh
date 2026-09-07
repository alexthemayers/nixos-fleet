#!/usr/bin/env bash
# Regenerate ssh/fleet_known_hosts from the operator's own known_hosts file.
#
# Run this from a workstation whose ~/.ssh/known_hosts entries you trust. It
# does not scan the network, because ssh-keyscan would happily record whatever
# answers on the wire and defeat the point of pinning host keys.
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-$HOME/.ssh/known_hosts}"
OUT="ssh/fleet_known_hosts"

HOSTS=(
  xcloud-caddy
  xcloud-postgres
  proxmox-applications-1
  proxmox-applications-2
  proxmox-observability
  proxmox-dev
  rpi4
  gaming
)

if [ ! -f "$SOURCE" ]; then
  echo "No such known_hosts file: $SOURCE" >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

{
  echo "# Fleet SSH host keys. Generated from a trusted admin workstation."
  echo "# Regenerate with: scripts/update-known-hosts.sh"
} >"$tmp"

missing=0
for host in "${HOSTS[@]}"; do
  found=0
  while read -r _ type key _; do
    case "$type" in
    ssh-ed25519 | ssh-rsa | ecdsa-sha2-*)
      echo "$host $type $key" >>"$tmp"
      found=1
      ;;
    esac
  done < <(ssh-keygen -F "$host" -f "$SOURCE" 2>/dev/null | grep -v '^#' || true)

  if [ "$found" -eq 0 ]; then
    echo "WARNING: no host key for $host in $SOURCE" >&2
    missing=1
  fi
done

mv "$tmp" "$OUT"
trap - EXIT

echo "Wrote $OUT"
[ "$missing" -eq 0 ] || echo "Some hosts were missing; $OUT is incomplete." >&2
