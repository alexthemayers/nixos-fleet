#!/usr/bin/env bash
# PromQL + Alertmanager config gates for the committed observability YAML.
# Wired into GitLab CI. Darwin local runs fail on the x86_64-only binaries;
# that is fine — CI on proxmox-dev is the merge gate (zero-debt: no CI gap).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

"$ROOT/scripts/check-mimir-rules.sh"
"$ROOT/scripts/check-alertmanager-config.sh"

echo "✓ Observability config checks passed"
