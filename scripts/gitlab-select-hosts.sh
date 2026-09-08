#!/usr/bin/env bash
# CI entry point: pick a baseline, write changed-hosts.json, generate the
# child pipeline YAML. Used by the select-hosts GitLab job.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ZERO_SHA="0000000000000000000000000000000000000000"

select_args=()
if [[ "${CI_PIPELINE_SOURCE:-}" =~ ^(web|pipeline)$ ]]; then
  select_args=(--all)
elif [ "${CI_COMMIT_BRANCH:-}" = "main" ] &&
  [ -n "${CI_COMMIT_BEFORE_SHA:-}" ] &&
  [ "$CI_COMMIT_BEFORE_SHA" != "$ZERO_SHA" ]; then
  select_args=("$CI_COMMIT_BEFORE_SHA")
else
  select_args=(origin/main)
fi

./scripts/changed-hosts.sh "${select_args[@]}" >changed-hosts.json

gen_args=(-o generated-pipeline.yml)
if [ "${CI_COMMIT_BRANCH:-}" = "main" ]; then
  gen_args+=(--deploy)
fi
./scripts/gitlab-gen-pipeline.sh "${gen_args[@]}" changed-hosts.json

echo "Changed hosts:"
python3 -c 'import json,sys; json.dump(json.load(open("changed-hosts.json")), sys.stdout, indent=2); print()'
