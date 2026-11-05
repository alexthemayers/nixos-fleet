#!/bin/bash
# Write Intel Xe GPU metrics for node_exporter's textfile collector.
# Same output as the NixOS intel-gpu-telemetry unit.
set -euo pipefail
out=/var/lib/prometheus/node-exporter/intel-gpu.prom
tmp="${out}.tmp.$$"
mkdir -p /var/lib/prometheus/node-exporter
gt_base=/sys/class/drm/card1/device/tile0
{
  echo "# HELP intel_gpu_frequency_actual_mhz Actual operating frequency of Intel Xe GPU engine"
  echo "# TYPE intel_gpu_frequency_actual_mhz gauge"
  echo "# HELP intel_gpu_frequency_cur_mhz Current requested frequency of Intel Xe GPU engine"
  echo "# TYPE intel_gpu_frequency_cur_mhz gauge"
  echo "# HELP intel_gpu_frequency_max_mhz Maximum frequency of Intel Xe GPU engine"
  echo "# TYPE intel_gpu_frequency_max_mhz gauge"
  echo "# HELP intel_gpu_frequency_min_mhz Minimum frequency of Intel Xe GPU engine"
  echo "# TYPE intel_gpu_frequency_min_mhz gauge"
  echo "# HELP intel_gpu_active_status Whether Intel Xe GPU tile is active (1) or sleeping in RC6 (0)"
  echo "# TYPE intel_gpu_active_status gauge"
  echo "# HELP intel_gpu_idle_residency_ms_total Cumulative idle residency of Intel Xe GPU tile in milliseconds"
  echo "# TYPE intel_gpu_idle_residency_ms_total counter"
  for gt in gt0 gt1; do
    if [ -d "$gt_base/$gt" ]; then
      act=$(cat "$gt_base/$gt/freq0/act_freq" 2>/dev/null || echo 0)
      cur=$(cat "$gt_base/$gt/freq0/cur_freq" 2>/dev/null || echo 0)
      max=$(cat "$gt_base/$gt/freq0/max_freq" 2>/dev/null || echo 0)
      min=$(cat "$gt_base/$gt/freq0/min_freq" 2>/dev/null || echo 0)
      status=$(cat "$gt_base/$gt/gtidle/idle_status" 2>/dev/null || echo unknown)
      idle_ms=$(cat "$gt_base/$gt/gtidle/idle_residency_ms" 2>/dev/null || echo 0)
      active=1
      if [ "$status" = gt-c6 ] || [ "$status" = gt-rc6 ]; then
        active=0
      fi
      printf 'intel_gpu_frequency_actual_mhz{gt="%s"} %s\n' "$gt" "$act"
      printf 'intel_gpu_frequency_cur_mhz{gt="%s"} %s\n' "$gt" "$cur"
      printf 'intel_gpu_frequency_max_mhz{gt="%s"} %s\n' "$gt" "$max"
      printf 'intel_gpu_frequency_min_mhz{gt="%s"} %s\n' "$gt" "$min"
      printf 'intel_gpu_active_status{gt="%s",status="%s"} %s\n' "$gt" "$status" "$active"
      printf 'intel_gpu_idle_residency_ms_total{gt="%s"} %s\n' "$gt" "$idle_ms"
    fi
  done
  echo "# HELP intel_gpu_drm_clients_total Count of processes holding open DRM file descriptors to Intel GPU"
  echo "# TYPE intel_gpu_drm_clients_total gauge"
  clients_file=/sys/kernel/debug/dri/1/clients
  clients=0
  if [ -r "$clients_file" ]; then
    total_lines=$(wc -l < "$clients_file" || echo 1)
    if [ "$total_lines" -gt 1 ]; then
      clients=$((total_lines - 1))
    fi
  fi
  echo "intel_gpu_drm_clients_total $clients"
  echo "# HELP intel_gpu_resets_total Count of GPU engine resets or driver wedged events this boot"
  echo "# TYPE intel_gpu_resets_total counter"
  resets=$(journalctl -k -b --no-pager -q 2>/dev/null | grep -ciE 'xe.*(gpu hang|engine reset|wedged)' || true)
  echo "intel_gpu_resets_total ${resets:-0}"
} > "$tmp"
mv -f "$tmp" "$out"
