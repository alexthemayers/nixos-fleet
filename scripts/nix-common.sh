# shellcheck shell=bash
# Sourced by deploy-host.sh, changed-hosts.sh, nix-develop.sh,
# check-mimir-rules.sh, and run-jellyfin-io-bench.sh. Not meant to be
# executed.
#
# Builder commands pass these substituters on the CLI. Host nix.conf lists
# cache.nixos.org (and the Raspberry Pi cachix on rpi4). The CLI override
# still matters for the first switch, while a running nix.conf may point
# at the removed Attic URL.
# docs/adr/2026-11-03-decommission-attic.md

CACHE_NIXOS_ORG_KEY="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
RPI_CACHIX_KEY="nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="

# Prefer the real Nix binary. Some builder hosts put a wrapper first on PATH.
nix_bin() {
  local candidate
  for candidate in /run/current-system/sw/bin/nix /nix/var/nix/profiles/default/bin/nix; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return
    fi
  done
  command -v nix
}

current_nix_system() {
  local nix="${NIX:-$(nix_bin)}"
  "$nix" eval --impure --raw --expr 'builtins.currentSystem'
}

# True when this builder's currentSystem matches $1. aarch64 work runs on
# rpi4, not under qemu on x86_64.
nix_can_run_system() {
  local want="$1"
  [ "$want" = "$(current_nix_system)" ]
}

# aarch64 builders also need the Pi cachix. Other systems use cache.nixos.org.
use_builder_cache() {
  local system="${1:-$(current_nix_system)}"
  if [ "$system" = "aarch64-linux" ]; then
    BUILDER_SUBSTITUTERS="https://cache.nixos.org https://nixos-raspberrypi.cachix.org"
    BUILDER_TRUSTED_PUBLIC_KEYS="${CACHE_NIXOS_ORG_KEY} ${RPI_CACHIX_KEY}"
  else
    BUILDER_SUBSTITUTERS="https://cache.nixos.org"
    BUILDER_TRUSTED_PUBLIC_KEYS="${CACHE_NIXOS_ORG_KEY}"
  fi
}

# Evals and builds must not follow a running nix.conf that still lists Attic.
# extra-substituters is cleared so CI NIX_CONFIG cannot add it back.
nix_eval_with_builder() {
  local nix="${NIX:-$(nix_bin)}"
  use_builder_cache
  "$nix" eval "$@" \
    --option substituters "$BUILDER_SUBSTITUTERS" \
    --option extra-substituters "" \
    --option trusted-substituters "$BUILDER_SUBSTITUTERS" \
    --option trusted-public-keys "$BUILDER_TRUSTED_PUBLIC_KEYS" \
    --option narinfo-cache-negative-ttl 0
}

nix_build_with_builder() {
  local nix="${NIX:-$(nix_bin)}"
  use_builder_cache
  "$nix" build "$@" --print-out-paths --no-link -L \
    --option substituters "$BUILDER_SUBSTITUTERS" \
    --option extra-substituters "" \
    --option trusted-substituters "$BUILDER_SUBSTITUTERS" \
    --option trusted-public-keys "$BUILDER_TRUSTED_PUBLIC_KEYS" \
    --option narinfo-cache-negative-ttl 0
}
