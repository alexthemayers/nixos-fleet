#!/usr/bin/env bash
# Run ShellCheck on all scripts/*.sh. Prefer binary on PATH (.#ci-tools in CI).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not on PATH; realize .#ci-tools in CI or install shellcheck" >&2
  exit 1
fi

# Portable: avoid mapfile (Bash 4+) for Darwin /bin/bash.
set -- scripts/*.sh
if [ "$1" = "scripts/*.sh" ]; then
  echo "no scripts/*.sh found" >&2
  exit 1
fi

shellcheck --severity=warning "$@"
echo "✓ shellcheck ok ($# scripts)"
