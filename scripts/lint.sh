#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "Starting flake lint checks"
echo "========================================="

# Prefer python3+PyYAML from PATH (.#ci-tools in CI); fall back to nix-shell.
run_py() {
  if python3 -c 'import yaml' 2>/dev/null; then
    python3 "$@"
  else
    # %q keeps argument boundaries through nix-shell's `sh -c`.
    nix-shell -p python3Packages.pyyaml --run "python3 $(printf '%q ' "$@")"
  fi
}

# Evaluates x86_64-linux deploy-rs schema (and other flake outputs).
# Per-host drvPath loops were redundant with this.
echo "Running nix flake check --all-systems --no-build..."
nix flake check --all-systems --no-build --show-trace
echo "✓ Flake checks passed"
echo ""

echo "Checking alert rule hygiene..."
run_py scripts/check-alert-rules.py \
  collections/ansible_collections/fleet/debian_guest/roles/observability/files/rules.yaml
echo "✓ Alert rule hygiene passed"
echo ""

echo "Checking Prometheus scrape targets against inventory..."
hosts_json=$(mktemp)
trap 'rm -f "$hosts_json"' EXIT
nix eval --json \
  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.hosts' \
  >"$hosts_json"
run_py scripts/check-prometheus-scrapes.py \
  collections/ansible_collections/fleet/debian_guest/roles/observability/files/prometheus.yml \
  "$hosts_json"
echo ""

echo "========================================="
echo "✓ All configuration lint checks passed!"
echo "========================================="
