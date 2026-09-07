{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    nvtopPackages.intel
    libva-utils
  ];

  security.rtkit.enable = true;

  boot.kernelParams = [
    "snd-hda-intel.dmic_detect=0"
    "module_blacklist=i915"
    "xe.force_probe=7d67"
  ];

  networking.hostName = "proxmox-applications-1";

  systemd.services.intel-gpu-telemetry = {
    description = "Intel Xe GPU telemetry exporter for node-exporter";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "intel-gpu-telemetry" ''
        set -euo pipefail
        OUT_DIR="/var/lib/prometheus-node-exporter"
        OUT_FILE="$OUT_DIR/intel-gpu.prom"
        TMP_FILE="$OUT_DIR/intel-gpu.prom.tmp.$$"

        mkdir -p "$OUT_DIR"

        GT_BASE="/sys/class/drm/card1/device/tile0"

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
            if [ -d "$GT_BASE/$gt" ]; then
              act=$(cat "$GT_BASE/$gt/freq0/act_freq" 2>/dev/null || echo 0)
              cur=$(cat "$GT_BASE/$gt/freq0/cur_freq" 2>/dev/null || echo 0)
              max=$(cat "$GT_BASE/$gt/freq0/max_freq" 2>/dev/null || echo 0)
              min=$(cat "$GT_BASE/$gt/freq0/min_freq" 2>/dev/null || echo 0)
              status=$(cat "$GT_BASE/$gt/gtidle/idle_status" 2>/dev/null || echo "unknown")
              idle_ms=$(cat "$GT_BASE/$gt/gtidle/idle_residency_ms" 2>/dev/null || echo 0)

              active=1
              if [ "$status" = "gt-c6" ] || [ "$status" = "gt-rc6" ]; then
                active=0
              fi

              echo "intel_gpu_frequency_actual_mhz{gt=\"$gt\"} $act"
              echo "intel_gpu_frequency_cur_mhz{gt=\"$gt\"} $cur"
              echo "intel_gpu_frequency_max_mhz{gt=\"$gt\"} $max"
              echo "intel_gpu_frequency_min_mhz{gt=\"$gt\"} $min"
              echo "intel_gpu_active_status{gt=\"$gt\",status=\"$status\"} $active"
              echo "intel_gpu_idle_residency_ms_total{gt=\"$gt\"} $idle_ms"
            fi
          done

          echo "# HELP intel_gpu_drm_clients_total Count of processes holding open DRM file descriptors to Intel GPU"
          echo "# TYPE intel_gpu_drm_clients_total gauge"
          clients_file="/sys/kernel/debug/dri/1/clients"
          clients=0
          if [ -r "$clients_file" ]; then
            total_lines=$(${pkgs.coreutils}/bin/wc -l < "$clients_file" || echo 1)
            if [ "$total_lines" -gt 1 ]; then
              clients=$((total_lines - 1))
            fi
          fi
          echo "intel_gpu_drm_clients_total $clients"

          echo "# HELP intel_gpu_resets_total Count of GPU engine resets or driver wedged events this boot"
          echo "# TYPE intel_gpu_resets_total counter"
          # Count from the kernel journal for the current boot, not the volatile
          # dmesg ring buffer. dmesg evicts old lines, so a reset event can
          # scroll out and make this counter drop between scrapes, which
          # Prometheus reads as a counter reset (a phantom spike, or a missed
          # IntelGPUDriverHang page). journalctl -k -b keeps the whole boot, so
          # the count is monotonic within a boot and resets only across reboots.
          resets=$(${pkgs.systemd}/bin/journalctl -k -b --no-pager -q 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep -ciE 'xe.*(gpu hang|engine reset|wedged)' || true)
          resets=''${resets:-0}
          echo "intel_gpu_resets_total $resets"
        } > "$TMP_FILE"

        mv -f "$TMP_FILE" "$OUT_FILE"
      '';
    };
  };

  systemd.timers.intel-gpu-telemetry = {
    description = "Run Intel Xe GPU telemetry exporter every 15s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10s";
      OnUnitActiveSec = "15s";
      AccuracySec = "1s";
    };
  };
}
