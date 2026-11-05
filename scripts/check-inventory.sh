#!/usr/bin/env bash
# Fail if the Makefile's host lists and config/fleet-inventory.nix disagree.
#
# Make and Nix cannot import each other, so the fleet inventory is duplicated by
# necessity. This check makes the duplication safe: the repo previously carried
# four hostnames in operator tooling that had not existed for months, which made
# `make reboot-all` skip seven live hosts while reporting success.
set -euo pipefail

cd "$(dirname "$0")/.."

nix_hosts=$(nix eval --json \
  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.nixosHosts' |
  python3 -c 'import sys,json; print("\n".join(sorted(json.load(sys.stdin))))')

make_hosts=$(make --no-print-directory print-hosts | tr ' ' '\n' | sed '/^$/d' | sort -u)

if ! diff -u --label nix <(echo "$nix_hosts") --label makefile <(echo "$make_hosts"); then
  echo "" >&2
  echo "The Makefile host lists and config/fleet-inventory.nix have drifted." >&2
  echo "Update both so they agree." >&2
  exit 1
fi

nix_paused=$(nix eval --json \
  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.deployPausedHosts' |
  python3 -c 'import sys,json; print("\n".join(sorted(json.load(sys.stdin))))')

make_paused=$(make --no-print-directory print-deploy-paused | tr ' ' '\n' | sed '/^$/d' | sort -u)

if ! diff -u --label nix <(echo "$nix_paused") --label makefile <(echo "$make_paused"); then
  echo "" >&2
  echo "Makefile DEPLOY_PAUSED and fleet.inventory.deployPausedHosts have drifted." >&2
  echo "Update both so they agree." >&2
  exit 1
fi

host_count=$(printf '%s\n' "$nix_hosts" | grep -c . || true)
paused_count=$(printf '%s\n' "$nix_paused" | grep -c . || true)
echo "✓ Makefile and fleet-inventory.nix agree (${host_count} hosts, ${paused_count} paused)"
