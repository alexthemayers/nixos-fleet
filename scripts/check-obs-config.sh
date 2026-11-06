#!/usr/bin/env bash
# PromQL + Alertmanager (+ Prometheus syntax) gates for committed YAML.
# Wired into GitLab CI. Prefer .#ci-tools on PATH (promtool, amtool, PyYAML).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

"$ROOT/scripts/check-mimir-rules.sh"
"$ROOT/scripts/check-alertmanager-config.sh"
python3 "$ROOT/scripts/check-dashboard-jobs.py"

PROM="$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/prometheus.yml"
if [ -f "$PROM" ]; then
  resolve_promtool() {
    if command -v promtool >/dev/null 2>&1; then
      command -v promtool
      return 0
    fi
    # shellcheck source=scripts/nix-common.sh
    source "$ROOT/scripts/nix-common.sh"
    local out
    out=$(nix_build_with_builder 'nixpkgs#prometheus.cli') || return 1
    printf '%s' "$out/bin/promtool"
  }
  echo "Checking prometheus.yml syntax..."
  promtool=$(resolve_promtool)
  # rule_files points at the guest path; --syntax-only skips missing files.
  if "$promtool" check config --help 2>&1 | grep -q syntax-only; then
    "$promtool" check config --syntax-only "$PROM"
  else
    # Older promtool: copy with local rule_files for a full check.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cp "$PROM" "$tmp/prometheus.yml"
    cp "$ROOT/collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml" \
      "$tmp/rules.yaml"
    # Rewrite rule_files to the temp dir.
    sed -i.bak 's|/etc/prometheus/rules.yaml|'"$tmp"'/rules.yaml|' "$tmp/prometheus.yml"
    "$promtool" check config "$tmp/prometheus.yml"
  fi
  echo "✓ prometheus.yml ok"
fi

echo "✓ Observability config checks passed"
