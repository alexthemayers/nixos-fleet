#!/usr/bin/env bash
# Instant-query a small allowlist of critical series against live Prometheus.
# Non-merge-blocking: scheduled / manual CI only (network + TSDB flakiness).
# See docs/adr alert-timeseries rule and docs/services/prometheus.md.
set -euo pipefail

PROM_URL="${PROM_URL:-http://proxmox-observability-debian:9090}"
# Series that must exist (instant query returns at least one sample).
QUERIES=(
  'up{job="prometheus"}'
  'up{job="node exporter"}'
  'up{job="loki"}'
  'up{job="grafana"}'
)

fail=0
for q in "${QUERIES[@]}"; do
  enc=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$q")
  body=$(curl -fsS --max-time 15 "${PROM_URL}/api/v1/query?query=${enc}") || {
    echo "query failed: $q (PROM_URL=$PROM_URL)" >&2
    fail=1
    continue
  }
  n=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("data",{}).get("result") or []))' <<<"$body")
  if [ "$n" -lt 1 ]; then
    echo "empty result: $q" >&2
    fail=1
  else
    echo "ok ($n series): $q"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "live PromQL sample failed against $PROM_URL" >&2
  exit 1
fi
echo "✓ live PromQL sample ok ($PROM_URL)"
