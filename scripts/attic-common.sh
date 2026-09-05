# Sourced by build.sh, deploy-from-attic.sh, attic-push.sh,
# verify-from-attic.sh, and nix-develop.sh. Not meant to be executed.
#
# Fill uses public substituters; realize/copy/switch and nix develop after
# fill use Attic only. See docs/adr/2026-08-30-attic-fill-then-exclusive.md.
#
# Required env:
#   ATTIC_TOKEN                 pull/push token (never commit; CI var or /root/.attic-token)
# Optional:
#   ATTIC_SKIP_IF_CACHED=1      skip fill when the full closure is already in Attic
#   ATTIC_BUILD_ALL_SYSTEMS=1   ignored for foreign architectures; aarch64
#                               fill/deploy run on rpi4 (scripts/run-on-rpi4.sh)
#   ATTIC_TOOLING_ONLY=1        build.sh: fill attic CLI + ci-tools + devShell, skip hosts
#   ATTIC_SKIP_TOOLING=1        deploy-from-attic.sh: fill the host only, not
#                               packages.attic / ci-tools / the default devShell
#                               (those pull a rustc deploy-rs on aarch64)
#   ATTIC_SKIP_FILL=1           deploy-from-attic.sh: do not fill; CI after verify
#   ATTIC_FORCE_SWITCH=1        deploy-from-attic.sh: switch even if toplevel matches
#   ATTIC_COPY_FROM_BUILDER=1   deploy hatch: nix copy from the builder store (cache hosts)
#   ATTIC_PUSH_JOBS=8           concurrent NAR uploads (needs Garage on LMDB)
#   ATTIC_PUSH_BATCH_SIZE=12    0 = one `attic push` of the closure; >0 batches paths

ATTIC_ENDPOINT="${ATTIC_ENDPOINT:-http://proxmox-dev:8080}"
ATTIC_CACHE_NAME="${ATTIC_CACHE_NAME:-attic}"
# attic-nar-proxy in front of atticd. Multi-chunk NARs stream as 200; Caddy
# on the LB still truncates those ("Transferred a partial file").
ATTIC_CACHE_URL="${ATTIC_CACHE_URL:-${ATTIC_ENDPOINT}/${ATTIC_CACHE_NAME}}"
# Single-chunk NARs (NAR < 64 KiB) 307 to a Garage presigned URL. Nix will
# not treat that as a valid substituter NAR; attic-nar-proxy follows it.
ATTIC_LB_URL="${ATTIC_LB_URL:-http://proxmox-lb:8080/${ATTIC_CACHE_NAME}}"
# Uncompressed store-path size below which we treat the NAR as single-chunk.
# Must match services/attic.nix chunking.nar-size-threshold.
ATTIC_SINGLE_CHUNK_MAX="${ATTIC_SINGLE_CHUNK_MAX:-65536}"
ATTIC_PUBLIC_KEY="${ATTIC_PUBLIC_KEY:-attic:4/oEWZvm70jexTDGnT/Xvv2wlV3cE4utycLPZUSbmAw=}"

CACHE_NIXOS_ORG_KEY="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
RPI_CACHIX_KEY="nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="

# Public substituters are allowed only while filling Attic. Deployed hosts
# never list them (config/system.nix). After fill, realize/copy/develop use
# ATTIC_CACHE_URL alone.
BUILDER_SUBSTITUTERS="${BUILDER_SUBSTITUTERS:-${ATTIC_CACHE_URL} https://cache.nixos.org https://nixos-raspberrypi.cachix.org}"
BUILDER_TRUSTED_PUBLIC_KEYS="${BUILDER_TRUSTED_PUBLIC_KEYS:-${ATTIC_PUBLIC_KEY} ${CACHE_NIXOS_ORG_KEY} ${RPI_CACHIX_KEY}}"

# Load ATTIC_TOKEN from the documented file if the env is empty. Never print it.
load_attic_token() {
  if [ -n "${ATTIC_TOKEN:-}" ]; then
    return 0
  fi
  local f="${ATTIC_TOKEN_FILE:-/root/.attic-token}"
  if [ -r "$f" ]; then
    ATTIC_TOKEN=$(cat "$f")
    export ATTIC_TOKEN
  fi
}

require_attic_token() {
  load_attic_token
  if [ -z "${ATTIC_TOKEN:-}" ]; then
    echo "ERROR: ATTIC_TOKEN is not set. Export it or put the JWT in /root/.attic-token" >&2
    exit 1
  fi
}

# Prefer the real Nix binary. Some builder hosts put a wrapper first on PATH
# that strips Attic substituters (truncated-NAR workaround). That wrapper must
# not be used for push or copy-from-Attic.
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

attic_login() {
  attic login "$ATTIC_CACHE_NAME" "$ATTIC_ENDPOINT" "$ATTIC_TOKEN"
}

# Push a store path and its closure. Concurrent uploads require Garage
# metadata on LMDB (services/garage.nix). Under sqlite, writers serialize and
# a parallel PutObject burst drove both db nodes into iowait until their S3
# and admin APIs stopped answering, at which point atticd 500'd every upload.
# Batches of 12 retry independently instead of failing a whole closure.
# Deploy db-1 and db-2 with ATTIC_PUSH_JOBS=1 while they are still on sqlite:
# docs/runbooks/garage-lmdb.md.
attic_push_closure() {
  local out_path="$1"
  local nix="${NIX:-$(nix_bin)}"
  local jobs="${ATTIC_PUSH_JOBS:-8}"
  local batch_size="${ATTIC_PUSH_BATCH_SIZE:-12}"
  local tmp p
  local -a batch=()

  _attic_push_batch() {
    if [ "$#" -eq 0 ]; then
      return 0
    fi
    local attempt
    for attempt in 1 2 3 4 5; do
      if attic push --ignore-upstream-cache-filter -j "$jobs" "$ATTIC_CACHE_NAME" "$@" >&2; then
        return 0
      fi
      echo "attic push failed (attempt $attempt/5), waiting 10s..." >&2
      sleep 10
    done
    return 1
  }

  if [ "$batch_size" -eq 0 ]; then
    _attic_push_batch "$out_path"
    return
  fi

  tmp=$(mktemp)
  "$nix" path-info -r "$out_path" >"$tmp"
  while read -r p; do
    [ -n "$p" ] || continue
    batch+=("$p")
    if [ "${#batch[@]}" -ge "$batch_size" ]; then
      _attic_push_batch "${batch[@]}"
      batch=()
    fi
  done <"$tmp"
  _attic_push_batch "${batch[@]}"
  rm -f "$tmp"
}

# Copy a closure onto a host from Attic only. The target never sees the
# builder store. Requires attic-nar-proxy (services/attic.nix) so
# single-chunk NARs are 200 rather than 307.
# ATTIC_COPY_FROM_BUILDER=1 is the bootstrap hatch for switching that
# proxy onto the Attic host (proxmox-dev) itself.
attic_copy_closure_to_ssh() {
  local host="$1"
  local out_path="$2"
  local nix="${NIX:-$(nix_bin)}"
  local dest="ssh://root@${host}"
  local attempt

  if [ "${ATTIC_COPY_FROM_BUILDER:-}" = 1 ]; then
    echo "Copying $out_path onto root@${host} from the builder store (ATTIC_COPY_FROM_BUILDER=1)..."
    for attempt in 1 2 3 4 5 6; do
      if "$nix" copy --to "$dest" "$out_path"; then
        return 0
      fi
      echo "nix copy to $dest failed (attempt $attempt/6), waiting 10s..." >&2
      sleep 10
    done
    echo "ERROR: nix copy onto root@${host} failed after retries" >&2
    return 1
  fi

  echo "Copying $out_path from Attic onto root@${host}..."
  for attempt in 1 2 3 4 5 6; do
    if "$nix" copy \
      --from "$ATTIC_CACHE_URL" \
      --to "$dest" \
      --option substituters "$ATTIC_CACHE_URL" \
      --option extra-substituters "" \
      --option trusted-substituters "$ATTIC_CACHE_URL" \
      --option trusted-public-keys "$ATTIC_PUBLIC_KEY" \
      --option fallback false \
      --option narinfo-cache-negative-ttl 0 \
      "$out_path"; then
      return 0
    fi
    echo "nix copy --from Attic failed (attempt $attempt/6), waiting 10s..." >&2
    sleep 10
  done
  echo "ERROR: nix copy --from Attic onto root@${host} failed after retries" >&2
  return 1
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

nixos_hosts_for_system() {
  local system="${1:-$(current_nix_system)}"
  local nix="${NIX:-$(nix_bin)}"
  "$nix" eval --raw .#nixosConfigurations --apply "x: let inherit (builtins) attrNames filter concatStringsSep; hostsForSystem = filter (name: x.\${name}.pkgs.stdenv.hostPlatform.system == \"$system\") (attrNames x); in concatStringsSep \" \" hostsForSystem"
}

nix_installable_system() {
  local attr="$1"
  local nix="${NIX:-$(nix_bin)}"
  "$nix" eval --raw "${attr}.system" 2>/dev/null || true
}

# Fill: substituters may include cache.nixos.org. extra-substituters is
# cleared so a host nix.conf or CI NIX_CONFIG cannot add more.
nix_build_with_builder() {
  local nix="${NIX:-$(nix_bin)}"
  "$nix" build "$@" --print-out-paths --no-link -L \
    --option substituters "$BUILDER_SUBSTITUTERS" \
    --option extra-substituters "" \
    --option trusted-substituters "$BUILDER_SUBSTITUTERS" \
    --option trusted-public-keys "$BUILDER_TRUSTED_PUBLIC_KEYS" \
    --option narinfo-cache-negative-ttl 0
}

# Exclusive realize: Attic only, no compile, no public cache.
nix_realize_attic_only() {
  local nix="${NIX:-$(nix_bin)}"
  "$nix" build "$@" --print-out-paths --no-link \
    --max-jobs 0 \
    --option substituters "$ATTIC_CACHE_URL" \
    --option extra-substituters "" \
    --option trusted-substituters "$ATTIC_CACHE_URL" \
    --option trusted-public-keys "$ATTIC_PUBLIC_KEY" \
    --option fallback false \
    --option narinfo-cache-negative-ttl 0
}

# True when every narinfo in the closure is on Attic (does not download NARs).
attic_closure_cached() {
  local path="$1"
  local nix="${NIX:-$(nix_bin)}"
  "$nix" path-info -r --store "$ATTIC_CACHE_URL" \
    --option trusted-public-keys "$ATTIC_PUBLIC_KEY" \
    --option narinfo-cache-negative-ttl 0 \
    "$path" >/dev/null 2>&1
}

# Build from public substituters if needed, push the closure, print the path.
# Progress goes to stderr so callers can capture stdout.
attic_fill_installable() {
  local attr="$1"
  local nix="${NIX:-$(nix_bin)}"
  local evaled out_path
  evaled=$("$nix" eval --raw "$attr")
  if [ "${ATTIC_SKIP_IF_CACHED:-}" = 1 ] && attic_closure_cached "$evaled"; then
    echo "Skipping $attr (closure already in Attic: $evaled)" >&2
    printf '%s\n' "$evaled"
    return 0
  fi
  local target_system
  target_system=$(nix_installable_system "$attr")
  if [ -n "$target_system" ] && ! nix_can_run_system "$target_system"; then
    echo "ERROR: $attr is $target_system; this builder is $(current_nix_system). aarch64 fill/deploy runs on rpi4: ./scripts/run-on-rpi4.sh ./scripts/build.sh" >&2
    return 1
  fi
  echo "Filling $attr (builder substituters, then attic push)..." >&2
  out_path=$(nix_build_with_builder "$attr")
  attic_push_closure "$out_path"
  printf '%s\n' "$out_path"
}

# attic CLI + ci-tools + default devShell. Hosts are filled separately.
attic_fill_tooling() {
  local system="${1:-$(current_nix_system)}"
  echo "Filling operator tooling for $system..." >&2
  if ! nix_can_run_system "$system"; then
    echo "ERROR: operator tooling for $system must be filled on that architecture (rpi4 for aarch64-linux: ./scripts/run-on-rpi4.sh ./scripts/build.sh)" >&2
    return 1
  fi
  attic_fill_installable ".#packages.${system}.attic" >/dev/null
  attic_fill_installable ".#packages.${system}.ci-tools" >/dev/null
  attic_fill_installable ".#devShells.${system}.default" >/dev/null
}

# Fill every current-system host in one nix build, then push each closure.
# Skip-if-cached hosts are left out of the build. Shared store paths are
# realized once instead of once per host.
attic_fill_hosts() {
  local host attr evaled
  local -a attrs=()
  local -a outs=()
  local nix="${NIX:-$(nix_bin)}"

  echo "Retrieving list of host configurations for $(current_nix_system)..." >&2
  if [ "${ATTIC_BUILD_ALL_SYSTEMS:-}" = 1 ]; then
    echo "ATTIC_BUILD_ALL_SYSTEMS=1 no longer fills foreign architectures; aarch64 runs on rpi4." >&2
  fi

  for host in $(nixos_hosts_for_system); do
    attr=".#deploy.nodes.${host}.profiles.system.path"
    evaled=$("$nix" eval --raw "$attr")
    if [ "${ATTIC_SKIP_IF_CACHED:-}" = 1 ] && attic_closure_cached "$evaled"; then
      echo "Skipping $attr (closure already in Attic: $evaled)" >&2
      continue
    fi
    attrs+=("$attr")
    outs+=("$evaled")
  done

  if [ "${#attrs[@]}" -eq 0 ]; then
    echo "All current-system hosts already in Attic" >&2
    return 0
  fi

  echo "Filling ${#attrs[@]} host(s) in one nix build..." >&2
  nix_build_with_builder "${attrs[@]}" >/dev/null

  local i
  for i in "${!attrs[@]}"; do
    attic_push_closure "${outs[$i]}"
    "$nix" store delete "${outs[$i]}" || true
  done
}

# Realize the attic CLI with builder substituters and put it on PATH so
# scripts do not need `nix develop` (which would compile stdenv on an
# Attic-only host). Push happens after attic_login.
ensure_attic_cli() {
  local system out_path
  system=$(current_nix_system)
  echo "Realizing attic CLI for $system (builder substituters)..." >&2
  out_path=$(nix_build_with_builder ".#packages.${system}.attic")
  export PATH="${out_path}/bin:${PATH}"
  ATTIC_CLI_PATH="$out_path"
}
