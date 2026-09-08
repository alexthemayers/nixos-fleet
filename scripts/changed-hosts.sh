#!/usr/bin/env bash
# Compare nixosConfigurations.*.config.system.build.toplevel outPaths at
# HEAD against a baseline git revision. Print JSON of hosts whose toplevel
# changed (plus x86 / rpi4 / gaming splits). Eval only; does not build.
#
# Usage: ./scripts/changed-hosts.sh [--all] [baseline]
#   --all         every current flake host (web / manual pipelines)
#   baseline      git revision (default: origin/main)
#
# If the baseline cannot be fetched or eval'd, falls back to --all.
# Does not require ATTIC_TOKEN.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# shellcheck source=attic-common.sh
source "$ROOT/scripts/attic-common.sh"

ALL=0
BASELINE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      ALL=1
      shift
      ;;
    -*)
      echo "Usage: $0 [--all] [baseline]" >&2
      exit 1
      ;;
    *)
      BASELINE="$1"
      shift
      ;;
  esac
done

APPLY='x: builtins.mapAttrs (n: v: { toplevel = "${v.config.system.build.toplevel}"; system = v.pkgs.stdenv.hostPlatform.system; }) x'

eval_hosts() {
  local flake="$1"
  local out="$2"
  nix_eval_with_builder --json "${flake}#nixosConfigurations" --apply "$APPLY" >"$out"
}

ZERO_SHA="0000000000000000000000000000000000000000"

ensure_git_rev() {
  local rev="$1"
  if git cat-file -e "${rev}^{commit}" 2>/dev/null; then
    git rev-parse --verify "${rev}^{commit}"
    return 0
  fi
  echo "Fetching $rev..." >&2
  if [[ "$rev" == origin/* ]]; then
    git fetch --depth=1 origin "${rev#origin/}" >&2
  else
    git fetch --depth=1 origin "$rev" >&2
  fi
  if git cat-file -e "${rev}^{commit}" 2>/dev/null; then
    git rev-parse --verify "${rev}^{commit}"
    return 0
  fi
  if git cat-file -e "FETCH_HEAD^{commit}" 2>/dev/null; then
    git rev-parse --verify "FETCH_HEAD^{commit}"
    return 0
  fi
  return 1
}

HEAD_JSON=$(mktemp)
BASE_JSON=$(mktemp)
trap 'rm -f "$HEAD_JSON" "$BASE_JSON"' EXIT

echo "Evaluating host toplevels at HEAD..." >&2
eval_hosts "." "$HEAD_JSON"

MODE="all"
BASELINE_SHA=""
if [ "$ALL" -eq 0 ]; then
  if [ -z "$BASELINE" ]; then
    BASELINE="origin/main"
  fi
  if [ "$BASELINE" = "$ZERO_SHA" ]; then
    echo "Baseline is zeros; selecting all hosts" >&2
    ALL=1
  elif [ ! -d "$ROOT/.git" ]; then
    echo "Not a git checkout; selecting all hosts" >&2
    ALL=1
  elif ! BASELINE_SHA=$(ensure_git_rev "$BASELINE"); then
    echo "WARNING: could not fetch $BASELINE; selecting all hosts" >&2
    ALL=1
  else
    echo "Evaluating host toplevels at $BASELINE_SHA..." >&2
    if ! eval_hosts "git+file://${ROOT}?rev=${BASELINE_SHA}&allRefs=1" "$BASE_JSON"; then
      echo "WARNING: could not eval $BASELINE_SHA; selecting all hosts" >&2
      ALL=1
    else
      MODE="diff"
    fi
  fi
fi

if [ "$ALL" -eq 1 ]; then
  MODE="all"
  echo '{}' >"$BASE_JSON"
fi

HEAD_REF=$(git rev-parse HEAD 2>/dev/null || echo "")

python3 - "$HEAD_JSON" "$BASE_JSON" "$MODE" "$BASELINE_SHA" "$HEAD_REF" <<'PY'
import json
import sys

head_path, base_path, mode, baseline, head_ref = sys.argv[1:]
with open(head_path, encoding="utf-8") as f:
    head = json.load(f)
with open(base_path, encoding="utf-8") as f:
    base = json.load(f)

hosts = []
x86 = []
rpi4 = []
gaming = []

for name, info in sorted(head.items()):
    toplevel = info["toplevel"]
    system = info["system"]
    prev = base.get(name)
    changed = mode == "all" or prev is None or prev.get("toplevel") != toplevel
    if not changed:
        continue
    hosts.append(name)
    if system == "aarch64-linux":
        rpi4.append(name)
    elif name == "gaming":
        gaming.append(name)
    else:
        x86.append(name)

json.dump(
    {
        "mode": mode,
        "baseline": baseline or None,
        "head": head_ref or None,
        "hosts": hosts,
        "x86": x86,
        "rpi4": rpi4,
        "gaming": gaming,
    },
    sys.stdout,
    indent=2,
)
print()
PY
