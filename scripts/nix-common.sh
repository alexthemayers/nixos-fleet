# shellcheck shell=bash
# Sourced by deploy-host.sh, changed-hosts.sh, nix-develop.sh,
# check-mimir-rules.sh, and run-jellyfin-io-bench.sh. Not meant to be
# executed.
#
# Builder commands pass these substituters on the CLI. Host nix.conf lists
# cache.nixos.org. The CLI override still matters for the first switch,
# so a stale builder nix.conf cannot redirect substituters.
# docs/adr/2026-11-03-decommission-attic.md

CACHE_NIXOS_ORG_KEY="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

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

# True when this builder's currentSystem matches $1.
nix_can_run_system() {
  local want="$1"
  [ "$want" = "$(current_nix_system)" ]
}

use_builder_cache() {
  BUILDER_SUBSTITUTERS="https://cache.nixos.org"
  BUILDER_TRUSTED_PUBLIC_KEYS="${CACHE_NIXOS_ORG_KEY}"
}

# Evals and builds pin public substituters on the CLI.
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
