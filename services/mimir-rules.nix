{
  config,
  lib,
  pkgs,
  ...
}:
let
  settingsFormat = pkgs.formats.yaml { };
  rulesData = {
    groups = [
      {
        name = "system";
        rules = [
          {
            alert = "HighCPUUsage";
            expr = ''100 - (avg by(host) (rate(node_cpu_seconds_total{mode="idle",host!~"m3pro|gaming"}[5m])) * 100) > 85'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High CPU usage on {{ $labels.host }}";
              description = "CPU usage is above 85% for 5 minutes";
            };
          }
          {
            alert = "HighMemoryUsage";
            expr = "(1 - (node_memory_MemAvailable_bytes{host!~\"proxmox|m3pro|gaming\"} / node_memory_MemTotal_bytes{host!~\"proxmox|m3pro|gaming\"})) * 100 > 85";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High memory usage on {{ $labels.host }}";
              description = "Memory usage is above 85% for 5 minutes";
            };
          }
          {
            alert = "ServiceDown";
            expr = ''systemd_unit_state{state="failed"} == 1'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Service failed on {{ $labels.instance }}";
              description = "Service {{ $labels.name }} is in failed state";
            };
          }
          {
            alert = "TargetDown";
            # Blackbox sets instance to the probed URL. When the prober is
            # down those series go 0 and this would page every public site.
            # EndpointDown covers probe_success; this job is scrape health.
            expr = ''up{job!="blackbox_http",instance!~"gaming.*",instance!~"m3pro.*",instance!~"rpi4.*"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Target {{ $labels.job }} is down";
              description = "{{ $labels.instance }} has been down for 5 minutes";
            };
          }
        ];
      }
      {
        # A unit that keeps restarting never settles into state="failed" for
        # long, so ServiceDown above can miss it entirely. Loki once restarted
        # 2800 times in a day against a Garage 503 without anyone being paged.
        name = "unit-crash-loops";
        rules = [
          {
            alert = "ServiceCrashLooping";
            expr = "increase(systemd_service_restart_total[15m]) > 5";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "{{ $labels.name }} is crash-looping on {{ $labels.instance }}";
              description = "{{ $labels.name }} restarted {{ $value | printf \"%.0f\" }} times in 15 minutes. Check `journalctl -u {{ $labels.name }}` for the failing dependency.";
            };
          }
          {
            alert = "ServiceRestartingRepeatedly";
            expr = "increase(systemd_service_restart_total[6h]) > 20";
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.name }} restarts frequently on {{ $labels.instance }}";
              description = "{{ $labels.name }} restarted {{ $value | printf \"%.0f\" }} times in 6 hours without ever staying failed.";
            };
          }
        ];
      }
      {
        # The nightly Postgres dump failed for 11 days with no operator-visible
        # signal. These rules are the cheapest coverage in this file.
        name = "backups";
        rules = [
          {
            alert = "BackupJobFailed";
            expr = ''systemd_unit_state{name=~"postgresqlBackup.service|gitlab-backup.service|gitlab-backup-sync.service",state="failed"} == 1'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Backup job {{ $labels.name }} failed on {{ $labels.instance }}";
              description = "{{ $labels.name }} is in the failed state. Backups are not reaching rpi4:/mnt/usb-backup until this is fixed.";
            };
          }
          {
            alert = "BackupTimerStale";
            # Both backups are nightly, so a gap beyond 48h means the timer is
            # not firing at all, which no failed-state alert can catch.
            expr = ''time() - systemd_timer_last_trigger_seconds{name=~"postgresqlBackup.timer|gitlab-backup.timer"} > 172800'';
            for = "1h";
            labels.severity = "critical";
            annotations = {
              summary = "Backup timer {{ $labels.name }} has not fired in 48h";
              description = "{{ $labels.name }} on {{ $labels.instance }} last triggered more than two days ago.";
            };
          }
        ];
      }
      {
        name = "blackbox-probe";
        rules = [
          {
            alert = "EndpointDown";
            expr = ''
              probe_success == 0
            '';
            for = "3m";
            labels.severity = "critical";
            annotations = {
              description = "The Blackbox Exporter failed to probe {{ $labels.instance }} for more than 3 minutes.";
              summary = "Endpoint {{ $labels.instance }} is down.";
            };
          }
        ];
      }
      {
        name = "node-exporter";
        rules = [
          {
            alert = "NodeFilesystemSpaceFillingUp";
            expr = ''
              (
                node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 15
              and
                predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"}[6h], 24*60*60) < 0
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "warning";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available space left and is filling up.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemspacefillingup";
              summary = "Filesystem is predicted to run out of space within the next 24 hours.";
            };
          }
          {
            alert = "NodeFilesystemSpaceFillingUp";
            expr = ''
              (
                node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 10
              and
                predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"}[6h], 4*60*60) < 0
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "critical";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available space left and is filling up fast.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemspacefillingup";
              summary = "Filesystem is predicted to run out of space within the next 4 hours.";
            };
          }
          {
            alert = "NodeFilesystemAlmostOutOfSpace";
            expr = ''
              (
                node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 5
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available space left.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemalmostoutofspace";
              summary = "Filesystem has less than 5% space left.";
            };
          }
          {
            alert = "NodeFilesystemAlmostOutOfSpace";
            expr = ''
              (
                node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 3
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "30m";
            labels.severity = "critical";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available space left.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemalmostoutofspace";
              summary = "Filesystem has less than 3% space left.";
            };
          }
          {
            alert = "NodeFilesystemFilesFillingUp";
            expr = ''
              (
                node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_files{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 40
              and
                predict_linear(node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"}[6h], 24*60*60) < 0
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "warning";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available inodes left and is filling up.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemfilesfillingup";
              summary = "Filesystem is predicted to run out of inodes within the next 24 hours.";
            };
          }
          {
            alert = "NodeFilesystemFilesFillingUp";
            expr = ''
              (
                node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_files{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 20
              and
                predict_linear(node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"}[6h], 4*60*60) < 0
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "critical";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available inodes left and is filling up fast.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemfilesfillingup";
              summary = "Filesystem is predicted to run out of inodes within the next 4 hours.";
            };
          }
          {
            alert = "NodeFilesystemAlmostOutOfFiles";
            expr = ''
              (
                node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_files{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 5
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "warning";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available inodes left.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemalmostoutoffiles";
              summary = "Filesystem has less than 5% inodes left.";
            };
          }
          {
            alert = "NodeFilesystemAlmostOutOfFiles";
            expr = ''
              (
                node_filesystem_files_free{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} / node_filesystem_files{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} * 100 < 3
              and
                node_filesystem_readonly{fstype!~"tmpfs|overlay",fstype!="",mountpoint!="",host!~"m3pro|gaming"} == 0
              )
            '';
            for = "1h";
            labels.severity = "critical";
            annotations = {
              description = ''Filesystem on {{ $labels.device }}, mounted on {{ $labels.mountpoint }}, at {{ $labels.instance }} has only {{ printf "%.2f" $value }}% available inodes left.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefilesystemalmostoutoffiles";
              summary = "Filesystem has less than 3% inodes left.";
            };
          }
          {
            alert = "NodeNetworkReceiveErrs";
            expr = "rate(node_network_receive_errs_total[2m]) / rate(node_network_receive_packets_total[2m]) > 0.01";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              description = ''{{ $labels.instance }} interface {{ $labels.device }} has encountered {{ printf "%.0f" $value }} receive errors in the last two minutes.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodenetworkreceiveerrs";
              summary = "Network interface is reporting many receive errors.";
            };
          }
          {
            alert = "NodeNetworkTransmitErrs";
            expr = "rate(node_network_transmit_errs_total[2m]) / rate(node_network_transmit_packets_total[2m]) > 0.01";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              description = ''{{ $labels.instance }} interface {{ $labels.device }} has encountered {{ printf "%.0f" $value }} transmit errors in the last two minutes.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodenetworktransmiterrs";
              summary = "Network interface is reporting many transmit errors.";
            };
          }
          {
            alert = "NodeHighNumberConntrackEntriesUsed";
            expr = "(node_nf_conntrack_entries / node_nf_conntrack_entries_limit) > 0.75";
            labels.severity = "warning";
            annotations = {
              description = "{{ $labels.instance }} {{ $value | humanizePercentage }} of conntrack entries are used.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodehighnumberconntrackentriesused";
              summary = "Number of conntrack are getting close to the limit.";
            };
          }
          {
            alert = "NodeTextFileCollectorScrapeError";
            expr = "node_textfile_scrape_error == 1";
            labels.severity = "warning";
            annotations = {
              description = "Node Exporter text file collector on {{ $labels.instance }} failed to scrape.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodetextfilecollectorscrapeerror";
              summary = "Node Exporter text file collector failed to scrape.";
            };
          }
          {
            alert = "NodeClockSkewDetected";
            expr = ''
              (
                node_timex_offset_seconds > 0.05
              and
                deriv(node_timex_offset_seconds[5m]) >= 0
              )
              or
              (
                node_timex_offset_seconds < -0.05
              and
                deriv(node_timex_offset_seconds[5m]) <= 0
              )
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "Clock at {{ $labels.instance }} is out of sync by more than 0.05s. Ensure NTP is configured correctly on this host.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodeclockskewdetected";
              summary = "Clock skew detected.";
            };
          }
          {
            alert = "NodeClockNotSynchronising";
            expr = ''
              min_over_time(node_timex_sync_status[5m]) == 0
              and
              node_timex_maxerror_seconds >= 16
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "Clock at {{ $labels.instance }} is not synchronising. Ensure NTP is configured on this host.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodeclocknotsynchronising";
              summary = "Clock not synchronising.";
            };
          }
          {
            alert = "NodeFileDescriptorLimit";
            expr = "(node_filefd_allocated * 100 / node_filefd_maximum > 70)";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''File descriptors limit at {{ $labels.instance }} is currently at {{ printf "%.2f" $value }}%.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefiledescriptorlimit";
              summary = "Kernel is predicted to exhaust file descriptors limit soon.";
            };
          }
          {
            alert = "NodeFileDescriptorLimit";
            expr = "(node_filefd_allocated * 100 / node_filefd_maximum > 90)";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = ''File descriptors limit at {{ $labels.instance }} is currently at {{ printf "%.2f" $value }}%.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodefiledescriptorlimit";
              summary = "Kernel is predicted to exhaust file descriptors limit soon.";
            };
          }
          {
            alert = "NodeSystemSaturation";
            expr = ''node_load1 / count without (cpu, mode) (node_cpu_seconds_total{mode="idle"}) > 2'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = "System load per core at {{ $labels.instance }} has been above 2 for the last 15 minutes, is currently at {{ printf \"%.2f\" $value }}.\nThis might indicate this instance resources saturation and can cause it becoming unresponsive.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodesystemsaturation";
              summary = "System saturated, load per core is very high.";
            };
          }
          {
            alert = "NodeMemoryMajorPagesFaults";
            expr = "rate(node_vmstat_pgmajfault[5m]) > 500";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = "Memory major pages are occurring at very high rate at {{ $labels.instance }}, 500 major page faults per second for the last 15 minutes, is currently at {{ printf \"%.2f\" $value }}.\nPlease check that there is enough memory available at this instance.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodememorymajorpagesfaults";
              summary = "Memory major page faults are occurring at very high rate.";
            };
          }
          {
            alert = "NodeDiskIOSaturation";
            expr = ''rate(node_disk_io_time_weighted_seconds_total{device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}[5m]) > 10'';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              description = "Disk IO queue (aqu-sq) is high on {{ $labels.device }} at {{ $labels.instance }}, has been above 10 for the last 30 minutes, is currently at {{ printf \"%.2f\" $value }}.\nThis symptom might indicate disk saturation.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodediskiosaturation";
              summary = "Disk IO queue is high.";
            };
          }
          {
            alert = "NodeIOWaitHigh";
            expr = ''avg by (instance) (rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100 > 20'';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "I/O wait time on {{ $labels.instance }} is > 20% for 10 minutes. Storage is struggling to keep up with the workload.";
              summary = "High I/O wait on {{ $labels.instance }}.";
            };
          }
          {
            alert = "NodeInterruptStorm";
            expr = "rate(node_context_switches_total[5m]) > 100000 or rate(node_intr_total[5m]) > 100000";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              description = "The hypervisor {{ $labels.instance }} is experiencing an unusually high rate of interrupts or context switches. Check for malfunctioning VM network drivers or SR-IOV issues.";
              summary = "Hardware interrupt or context switch storm detected.";
            };
          }
        ];
      }
      {
        name = "node-exporter.rules";
        rules = [
          {
            record = "instance:node_num_cpu:sum";
            expr = ''count without (cpu, mode) (node_cpu_seconds_total{mode="idle"})'';
          }
          {
            record = "instance:node_cpu_utilisation:rate5m";
            expr = ''1 - avg without (cpu) (sum without (mode) (rate(node_cpu_seconds_total{mode=~"idle|iowait|steal"}[5m])))'';
          }
          {
            record = "instance:node_load1_per_cpu:ratio";
            expr = "(node_load1 / instance:node_num_cpu:sum)";
          }
          {
            record = "instance:node_memory_utilisation:ratio";
            expr = ''
              1 - (
                (
                  node_memory_MemAvailable_bytes
                  or
                  (
                    node_memory_Buffers_bytes
                    +
                    node_memory_Cached_bytes
                    +
                    node_memory_MemFree_bytes
                    +
                    node_memory_Slab_bytes
                  )
                )
              /
                node_memory_MemTotal_bytes
              )
            '';
          }
          {
            record = "instance:node_vmstat_pgmajfault:rate5m";
            expr = "rate(node_vmstat_pgmajfault[5m])";
          }
          {
            record = "instance_device:node_disk_io_time_seconds:rate5m";
            expr = ''rate(node_disk_io_time_seconds_total{device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}[5m])'';
          }
          {
            record = "instance_device:node_disk_io_time_weighted_seconds:rate5m";
            expr = ''rate(node_disk_io_time_weighted_seconds_total{device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}[5m])'';
          }
          {
            record = "instance:node_network_receive_bytes_excluding_lo:rate5m";
            expr = ''sum without (device) (rate(node_network_receive_bytes_total{device!="lo"}[5m]))'';
          }
          {
            record = "instance:node_network_transmit_bytes_excluding_lo:rate5m";
            expr = ''sum without (device) (rate(node_network_transmit_bytes_total{device!="lo"}[5m]))'';
          }
          {
            record = "instance:node_network_receive_drop_excluding_lo:rate5m";
            expr = ''sum without (device) (rate(node_network_receive_drop_total{device!="lo"}[5m]))'';
          }
          {
            record = "instance:node_network_transmit_drop_excluding_lo:rate5m";
            expr = ''sum without (device) (rate(node_network_transmit_drop_total{device!="lo"}[5m]))'';
          }
          {
            record = "instance:node_network_receive_bytes_physical:rate5m";
            expr = ''sum without (device) (rate(node_network_receive_bytes_total{device!~"lo|veth.+"}[5m]))'';
          }
          {
            record = "instance:node_network_transmit_bytes_physical:rate5m";
            expr = ''sum without (device) (rate(node_network_transmit_bytes_total{device!~"lo|veth.+"}[5m]))'';
          }
          {
            record = "instance:node_network_receive_drop_physical:rate5m";
            expr = ''sum without (device) (rate(node_network_receive_drop_total{device!~"lo|veth.+"}[5m]))'';
          }
          {
            record = "instance:node_network_transmit_drop_physical:rate5m";
            expr = ''sum without (device) (rate(node_network_transmit_drop_total{device!~"lo|veth.+"}[5m]))'';
          }
        ];
      }
      {
        name = "prometheus";
        rules = [
          {
            alert = "PrometheusBadConfig";
            expr = "max_over_time(prometheus_config_last_reload_successful[5m]) == 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              description = "Prometheus {{$labels.instance}} has failed to reload its configuration.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusbadconfig";
              summary = "Failed Prometheus configuration reload.";
            };
          }
          # Agent mode exports no prometheus_notifications_*, prometheus_rule_*,
          # or prometheus_sd_refresh_failures_total. The ruler covers those
          # signals as cortex_prometheus_* / cortex_ruler_*.
          {
            alert = "PrometheusTSDBReloadsFailing";
            expr = "increase(prometheus_tsdb_reloads_failures_total[3h]) > 0";
            for = "4h";
            labels.severity = "warning";
            annotations = {
              description = "Prometheus {{$labels.instance}} has detected {{$value | humanize}} reload failures over the last 3h.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheustsdbreloadsfailing";
              summary = "Prometheus has issues reloading blocks from disk.";
            };
          }
          {
            alert = "PrometheusTSDBCompactionsFailing";
            expr = "increase(prometheus_tsdb_compactions_failed_total[3h]) > 0";
            for = "4h";
            labels.severity = "warning";
            annotations = {
              description = "Prometheus {{$labels.instance}} has detected {{$value | humanize}} compaction failures over the last 3h.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheustsdbcompactionsfailing";
              summary = "Prometheus has issues compacting blocks.";
            };
          }
          {
            alert = "PrometheusNotIngestingSamples";
            expr = ''
              (
                sum without(type) (rate(prometheus_tsdb_head_samples_appended_total[5m])) <= 0
              and
                (
                  sum without(scrape_job) (prometheus_target_metadata_cache_entries) > 0
                or
                  sum without(rule_group) (prometheus_rule_group_rules) > 0
                )
              )
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "Prometheus {{$labels.instance}} is not ingesting samples.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusnotingestingsamples";
              summary = "Prometheus is not ingesting samples.";
            };
          }
          {
            alert = "PrometheusDuplicateTimestamps";
            expr = "rate(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m]) > 0";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} is dropping {{ printf "%.4g" $value }} samples/s with different values but duplicated timestamp.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusduplicatetimestamps";
              summary = "Prometheus is dropping samples with duplicate timestamps.";
            };
          }
          {
            alert = "PrometheusOutOfOrderTimestamps";
            expr = "rate(prometheus_target_scrapes_sample_out_of_order_total[5m]) > 0";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} is dropping {{ printf "%.4g" $value }} samples/s with timestamps arriving out of order.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusoutofordertimestamps";
              summary = "Prometheus drops samples with out-of-order timestamps.";
            };
          }
          {
            alert = "PrometheusRemoteStorageFailures";
            expr = ''
              (
                (rate(prometheus_remote_storage_failed_samples_total[5m]) or rate(prometheus_remote_storage_samples_failed_total[5m]))
              /
                (
                  (rate(prometheus_remote_storage_failed_samples_total[5m]) or rate(prometheus_remote_storage_samples_failed_total[5m]))
                +
                  (rate(prometheus_remote_storage_succeeded_samples_total[5m]) or rate(prometheus_remote_storage_samples_total[5m]))
                )
              )
              * 100
              > 1
            '';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = ''Prometheus {{$labels.instance}} failed to send {{ printf "%.1f" $value }}% of the samples to {{ $labels.remote_name}}:{{ $labels.url }}'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusremotestoragefailures";
              summary = "Prometheus fails to send samples to remote storage.";
            };
          }
          {
            alert = "PrometheusRemoteWriteBehind";
            expr = ''
              (
                max_over_time(prometheus_remote_storage_queue_highest_timestamp_seconds[5m])
              -
                max_over_time(prometheus_remote_storage_queue_highest_sent_timestamp_seconds[5m])
              )
              > 120
            '';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = ''Prometheus {{$labels.instance}} remote write is {{ printf "%.1f" $value }}s behind for {{ $labels.remote_name}}:{{ $labels.url }}.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusremotewritebehind";
              summary = "Prometheus remote write is behind.";
            };
          }
          {
            alert = "PrometheusRemoteWriteDesiredShards";
            expr = ''
              (
                max_over_time(prometheus_remote_storage_shards_desired[5m])
              >
                max_over_time(prometheus_remote_storage_shards_max[5m])
              )
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} remote write desired shards calculation wants to run {{ $value }} shards for queue {{ $labels.remote_name}}:{{ $labels.url }}, which is more than the max of {{ printf `prometheus_remote_storage_shards_max{instance="%s"}` $labels.instance | query | first | value }}.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusremotewritedesiredshards";
              summary = "Prometheus remote write desired shards calculation wants to run more than configured max shards.";
            };
          }
          {
            alert = "PrometheusTargetLimitHit";
            expr = "increase(prometheus_target_scrape_pool_exceeded_target_limit_total[5m]) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has dropped {{ printf "%.0f" $value }} targets because the number of targets exceeded the configured target_limit.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheustargetlimithit";
              summary = "Prometheus has dropped targets because some scrape configs have exceeded the targets limit.";
            };
          }
          {
            alert = "PrometheusLabelLimitHit";
            expr = "increase(prometheus_target_scrape_pool_exceeded_label_limits_total[5m]) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has dropped {{ printf "%.0f" $value }} targets because some samples exceeded the configured label_limit, label_name_length_limit or label_value_length_limit.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheuslabellimithit";
              summary = "Prometheus has dropped targets because some scrape configs have exceeded the labels limit.";
            };
          }
          {
            alert = "PrometheusScrapeBodySizeLimitHit";
            expr = "increase(prometheus_target_scrapes_exceeded_body_size_limit_total[5m]) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has failed {{ printf "%.0f" $value }} scrapes in the last 5m because some targets exceeded the configured body_size_limit.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusscrapebodysizelimithit";
              summary = "Prometheus has dropped some targets that exceeded body size limit.";
            };
          }
          {
            alert = "PrometheusScrapeSampleLimitHit";
            expr = "increase(prometheus_target_scrapes_exceeded_sample_limit_total[5m]) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has failed {{ printf "%.0f" $value }} scrapes in the last 5m because some targets exceeded the configured sample_limit.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusscrapesamplelimithit";
              summary = "Prometheus has failed scrapes that have exceeded the configured sample limit.";
            };
          }
          {
            alert = "PrometheusTargetSyncFailure";
            expr = "increase(prometheus_target_sync_failed_total[30m]) > 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              description = ''{{ printf "%.0f" $value }} targets in Prometheus {{$labels.instance}} have failed to sync because invalid configuration was supplied.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheustargetsyncfailure";
              summary = "Prometheus has failed to sync targets.";
            };
          }
          {
            alert = "PrometheusHighQueryLoad";
            expr = "avg_over_time(prometheus_engine_queries[5m]) / max_over_time(prometheus_engine_queries_concurrent_max[5m]) > 0.8";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = "Prometheus {{$labels.instance}} query API has less than 20% available capacity in its query engine for the last 15 minutes.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheushighqueryload";
              summary = "Prometheus is reaching its maximum capacity serving concurrent requests.";
            };
          }
        ];
      }
      {
        name = "GrafanaAlerts";
        rules = [
          {
            alert = "GrafanaRequestsFailing";
            expr = ''
              100 * sum without (status_code) (instance_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m{handler!~"/api/datasources/proxy/:id.*|/api/ds/query|/api/tsdb/query", status_code=~"5.."})
              /
              sum without (status_code) (instance_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m{handler!~"/api/datasources/proxy/:id.*|/api/ds/query|/api/tsdb/query"})
              > 50
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              # Upstream ships this as `message`, which the ntfy bridge does
              # not read; it templates summary and description only.
              summary = "Grafana is returning 5xx on {{ $labels.instance }}";
              description = "{{ $labels.instance }}/{{ $labels.job }}/{{ $labels.handler }} is experiencing {{ $value | humanize }}% errors";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/grafana/grafanarequestsfailing";
            };
          }
        ];
      }
      {
        name = "grafana_rules";
        rules = [
          {
            record = "instance_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m";
            expr = "sum by (instance, job, handler, status_code) (rate(grafana_http_request_duration_seconds_count[5m]))";
          }
        ];
      }
      {
        name = "tailscale-mesh";
        rules = [
          {
            alert = "TailscaleNodeUnreachable";
            # Assuming tailscale-client-metrics exposes reachability
            expr = ''up{job="tailscale-client-metrics",instance!~"gaming.*",instance!~"m3pro.*",instance!~"rpi4.*"} == 0'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "Tailscale node {{ $labels.tailscale_machine }} is offline";
              description = "Metrics endpoint unreachable. Node may be offline or tailscaled is crashed.";
            };
          }
          {
            alert = "TailscaleDERPRelaySpike";
            # clientmetrics path labels are derp / direct_ipv4 / direct_ipv6 /
            # peer_relay_*. tailscale_derp_io_bytes_total is not exported.
            # Every node keeps ~25 B/s of DERP keepalive; ignore that.
            expr = ''
              sum by (tailscale_machine) (
                rate(tailscaled_outbound_bytes_total{path="derp"}[5m])
              ) > 50000
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Heavy DERP relay usage on {{ $labels.tailscale_machine }}";
              description = "{{ $labels.tailscale_machine }} is sending more than 50 KiB/s through Tailscale DERP. Direct paths are failing or unused; expect high latency and low throughput.";
            };
          }
          {
            alert = "TailscaleNodeThroughputLowLocal";
            # Alert if local inter-VM throughput is under 1 Gbps (since they sit on the same hypervisor with SR-IOV VFs)
            expr = ''
              (
                (
                  node_network_throughput_iperf3_upload_bps{host=~"proxmox-.*", target=~"proxmox-.*"} < 1000000000
                  or
                  node_network_throughput_iperf3_download_bps{host=~"proxmox-.*", target=~"proxmox-.*"} < 1000000000
                )
                and
                node_network_throughput_iperf3_test_failed == 0
              )
              and
              (time() - node_network_throughput_iperf3_last_run_timestamp < 7200)
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Low local LAN throughput on {{ $labels.host }} to {{ $labels.target }}";
              description = "Active local speedtest throughput between {{ $labels.host }} and {{ $labels.target }} has dropped below 1 Gbps.";
            };
          }
          {
            alert = "TailscaleNodeThroughputLowWAN";
            # Alert if WAN or cross-site throughput is under 100 Mbps
            expr = ''
              (
                (
                  (node_network_throughput_iperf3_upload_bps unless node_network_throughput_iperf3_upload_bps{host=~"proxmox-.*", target=~"proxmox-.*"}) < 100000000
                  or
                  (node_network_throughput_iperf3_download_bps unless node_network_throughput_iperf3_download_bps{host=~"proxmox-.*", target=~"proxmox-.*"}) < 100000000
                )
                and
                node_network_throughput_iperf3_test_failed == 0
              )
              and
              (time() - node_network_throughput_iperf3_last_run_timestamp < 7200)
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Low WAN throughput on {{ $labels.host }} to {{ $labels.target }}";
              description = "Active cross-site speedtest throughput between {{ $labels.host }} and {{ $labels.target }} has dropped below 100 Mbps.";
            };
          }
          {
            alert = "TailscaleNodeThroughputTestFailed";
            # Alert if the iperf3 test coordinator consistently fails to execute a test
            expr = ''
              node_network_throughput_iperf3_test_failed == 1
              and
              (time() - node_network_throughput_iperf3_last_run_timestamp < 7200)
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Throughput speedtest failed on {{ $labels.host }}";
              description = "Active iperf3 speedtest from {{ $labels.host }} targeting {{ $labels.target }} has failed to complete.";
            };
          }
          {
            alert = "TailscaleNodeHighPacketLoss";
            # Alert if ICMP packet loss between nodes over Tailscale exceeds 2%
            # gaming/m3pro are desktops; TargetDown already excludes them.
            expr = ''
              (
                sum by (host, exported_host) (rate(smokeping_requests_total{exported_host!~"rpi4.*|gaming.*|m3pro.*"}[5m]))
                -
                sum by (host, exported_host) (rate(smokeping_response_duration_seconds_count{exported_host!~"rpi4.*|gaming.*|m3pro.*"}[5m]))
              )
              /
              sum by (host, exported_host) (rate(smokeping_requests_total{exported_host!~"rpi4.*|gaming.*|m3pro.*"}[5m])) * 100 > 2
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High packet loss between {{ $labels.host }} and {{ $labels.exported_host }}";
              description = "Packet loss between {{ $labels.host }} and {{ $labels.exported_host }} is at {{ $value | printf \"%.2f\" }}% over the last 5 minutes.";
            };
          }
          {
            alert = "TailscaleNodeHighLatency";
            # Alert if ping RTT between nodes over Tailscale exceeds 150ms
            expr = ''
              (
                sum by (host, exported_host) (rate(smokeping_response_duration_seconds_sum{exported_host!~"rpi4.*|gaming.*|m3pro.*"}[5m]))
                /
                sum by (host, exported_host) (rate(smokeping_response_duration_seconds_count{exported_host!~"rpi4.*|gaming.*|m3pro.*"}[5m]))
              ) * 1000 > 150
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High network latency between {{ $labels.host }} and {{ $labels.exported_host }}";
              description = "Average RTT latency between {{ $labels.host }} and {{ $labels.exported_host }} is {{ $value | printf \"%.0f\" }}ms.";
            };
          }
          {
            alert = "TailscaleNodeTCPRetransmissionRate";
            # Alert if host TCP retransmission rate is above 1.5% for local Proxmox VMs, or 5% for cloud WAN/legacy nodes
            expr = "((rate(node_netstat_Tcp_RetransSegs{host!~\"xcloud-.*|rpi4\"}[5m]) / rate(node_netstat_Tcp_OutSegs[5m]) * 100 > 1.5) and (rate(node_netstat_Tcp_OutSegs[5m]) > 10)) or ((rate(node_netstat_Tcp_RetransSegs{host=~\"xcloud-.*|rpi4\"}[5m]) / rate(node_netstat_Tcp_OutSegs[5m]) * 100 > 5) and (rate(node_netstat_Tcp_OutSegs[5m]) > 10))";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "High TCP retransmission rate on {{ $labels.host }}";
              description = "TCP retransmission rate is {{ $value | printf \"%.2f\" }}% over the last 5 minutes, indicating potential packet drop.";
            };
          }
          {
            alert = "TailscaleNodeUDPBufferErrors";
            # Alert if host UDP buffer drops are actively occurring
            expr = "rate(node_netstat_Udp_RcvbufErrors[5m]) > 5 or rate(node_netstat_Udp_SndbufErrors[5m]) > 5";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "UDP buffer errors on {{ $labels.host }}";
              description = "UDP receive/send buffer drops are occurring at a rate of {{ $value | printf \"%.1f\" }} errors/sec.";
            };
          }
          {
            alert = "TailscaleConnectionRelayed";
            # path="direct" does not exist; the series are direct_ipv4 / direct_ipv6.
            expr = ''
              sum by (tailscale_machine) (
                rate(tailscaled_outbound_bytes_total{path="derp"}[10m])
              ) > 1024
              and
              sum by (tailscale_machine) (
                rate(tailscaled_outbound_bytes_total{path=~"direct_.*"}[10m])
              ) == 0
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Tailscale node {{ $labels.tailscale_machine }} is using DERP relays exclusively";
              description = "No direct IPv4/IPv6 path. Real outbound traffic (>1 KiB/s) is only on path=derp. Check NAT / UDP 41641 and `tailscale status` on {{ $labels.tailscale_machine }}.";
            };
          }
          {
            alert = "TailscaleDERPInsteadOfDirect";
            # Majority of bytes on DERP while there is still some direct: NAT
            # half-failed. Keepalive-only DERP is a few dozen B/s and stays
            # under the 10 KiB/s floor.
            expr = ''
              (
                sum by (tailscale_machine) (
                  rate(tailscaled_outbound_bytes_total{path="derp"}[10m])
                )
                /
                sum by (tailscale_machine) (
                  rate(tailscaled_outbound_bytes_total[10m])
                )
              ) > 0.5
              and
              sum by (tailscale_machine) (
                rate(tailscaled_outbound_bytes_total{path="derp"}[10m])
              ) > 10240
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Most Tailscale traffic on {{ $labels.tailscale_machine }} is relayed via DERP";
              description = "{{ $value | humanizePercentage }} of outbound bytes on {{ $labels.tailscale_machine }} are going through DERP instead of a direct path.";
            };
          }
        ];
      }
      {
        name = "kernel-stability";
        rules = [
          {
            alert = "KernelOOMKills";
            # Catches the Out-Of-Memory killer terminating processes
            expr = "increase(node_vmstat_oom_kill[5m]) > 0";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "OOM Killer invoked on {{ $labels.host }}";
              description = "The kernel killed a process due to memory exhaustion. Check `dmesg` to identify the terminated service.";
            };
          }
          # NixOSConfigurationFailed was dropped: it watched
          # nixos-upgrade.service, which this fleet has never enabled (deploys
          # go through deploy-rs). It could neither fire true nor fire false.
        ];
      }
      {
        name = "hardware-hypervisor";
        rules = [
          {
            alert = "ProxmoxCPUTemperatureHigh";
            expr = ''node_hwmon_temp_celsius{host="proxmox",chip="platform_coretemp_0",sensor="temp1"} > 80'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Proxmox CPU package temperature > 80°C";
              description = "CPU package temperature is {{ $value }}°C. Check AIO cooler and fan curves on the hypervisor.";
            };
          }
          {
            alert = "ProxmoxCPUTemperatureCritical";
            expr = ''node_hwmon_temp_celsius{host="proxmox",chip="platform_coretemp_0",sensor="temp1"} > 90'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "Proxmox CPU package temperature > 90°C";
              description = "CPU package temperature is critical ({{ $value }}°C). Thermal shutdown imminent.";
            };
          }
          {
            alert = "ProxmoxCPUThrottlingActive";
            expr = ''increase(node_cpu_package_throttles_total{host="proxmox"}[5m]) > 0'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Intel CPU thermal throttling active on hypervisor";
              description = "The CPU package throttled {{ $value | printf \"%.0f\" }} times in the last 5 minutes due to thermal headroom breach.";
            };
          }
          {
            alert = "ProxmoxHostSwapping";
            # Gate on actual swap I/O (pages moved in/out of swap), not
            # node_vmstat_pgpgin, which counts *all* block-device page-ins
            # (ordinary file reads, backups, Attic pulls) and is not a swap
            # signal. 100 pages/s (~400 KiB/s) sustained for 10m is genuine
            # thrashing rather than an idle system touching swap once.
            expr = ''(rate(node_vmstat_pswpin{host="proxmox"}[5m]) + rate(node_vmstat_pswpout{host="proxmox"}[5m])) > 100'';
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Proxmox hypervisor is heavily swapping guest memory";
              description = "Hypervisor is moving {{ $value | printf \"%.0f\" }} pages/sec in+out of swap. Physical RAM is exhausted; VM pages are going to disk, causing massive latency.";
            };
          }
          {
            alert = "VFIODriverUnbound";
            # The gauge is label-stable (no driver label): 1 when bound to
            # vfio-pci, 0 otherwise. Matching on a driver label here would make
            # this a dead alert, because a hijacked device changes the label set
            # and the == 0 comparison would select no series. The bound driver
            # string is on node_hardware_pci_driver_info for context.
            expr = ''node_hardware_pci_driver_bound{device_name="igpu"} == 0'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "Intel iGPU is not bound to vfio-pci on hypervisor";
              description = "Device 0000:00:02.0 is not claimed by vfio-pci. Host GPU drivers or boot failure broke passthrough to proxmox-applications-1.";
            };
          }
          {
            alert = "SRIOVVirtualFunctionsMissing";
            expr = ''node_sriov_numvfs_configured{interface="enp2s0f1np1"} < 16'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "SR-IOV Virtual Functions missing on enp2s0f1np1";
              description = "Only {{ $value }} VFs are configured on enp2s0f1np1 (expected 16). Guest VMs may fail to attach SR-IOV NICs.";
            };
          }
          {
            alert = "HardwareMCEError";
            expr = "increase(node_ras_mce_records_total[1h]) > 0";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Machine Check Exception recorded on hypervisor";
              description = "rasdaemon recorded {{ $value }} hardware MCE events. Check `ras-mc-ctl --summary` or dmesg.";
            };
          }
          {
            alert = "PCIeAERErrorsHigh";
            # rasdaemon's aer_event table is authoritative and monotonic (rows
            # are only ever inserted), unlike a kernel-log substring scan. Any
            # AER event on this passthrough host is worth a look: a flaky PCIe
            # link to the X710 or iGPU degrades SR-IOV and GPU transcoding.
            expr = "increase(node_ras_aer_events_total[15m]) > 0";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "PCIe AER errors recorded on hypervisor";
              description = "rasdaemon recorded {{ $value }} PCIe Advanced Error Reporting events in 15m. Check `ras-mc-ctl --summary` and `lspci -vv` link status.";
            };
          }
          {
            alert = "ProxmoxHardwareErrorBERT";
            # The firmware wrote an ACPI BERT fatal error record for the boot
            # before this one: the last crash was a hardware fault (Intel SoC
            # CrashLog / uncorrectable package error), not software. Persists
            # until a clean reboot clears the record. See the crash runbook.
            expr = ''node_hardware_bert_error_records{host="proxmox"} > 0'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Firmware recorded a fatal hardware error at last boot (ACPI BERT)";
              description = "The hypervisor booted with {{ $value }} ACPI BERT fatal error record(s). The previous shutdown was a hardware crash, not a reboot. Decode it and act: docs/runbooks/proxmox-hardware-crash.md.";
            };
          }
          {
            alert = "ProxmoxBERTDisabled";
            # bert_disable is a boolean kernel flag. Presence — including
            # bert_disable=0 — disables ACPI BERT parsing, so a fatal SoC
            # crash leaves node_hardware_bert_error_records at 0 and
            # ProxmoxHardwareErrorBERT never fires.
            expr = ''node_hardware_bert_enabled{host="proxmox"} == 0'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "ACPI BERT parsing is disabled on the hypervisor";
              description = "The kernel logged that Boot Error Record Table support is disabled. Remove bert_disable from the GRUB cmdline (it is a boolean; =0 still disables it) and reboot. Until then hardware-crash records are invisible.";
            };
          }
          {
            alert = "ProxmoxMemoryPressureHigh";
            # Overcommit is the standing risk on this 96 GiB box (~82 GiB of VM
            # RAM + ~9.4 GiB ZFS ARC). Baseline sits ~92%, so gate above that.
            # Sustained near-exhaustion stresses the IMC/VRMs and precedes swap
            # thrashing and the Sept 4 hardware crash conditions.
            expr = ''(1 - (node_memory_MemAvailable_bytes{host="proxmox"} / node_memory_MemTotal_bytes{host="proxmox"})) * 100 > 95'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Proxmox hypervisor memory pressure high";
              description = "Hypervisor memory is {{ $value | printf \"%.1f\" }}% used for 15m. Reduce VM RAM commit or ZFS ARC before it exhausts and swaps.";
            };
          }
          {
            alert = "ProxmoxMemoryPressureCritical";
            expr = ''(1 - (node_memory_MemAvailable_bytes{host="proxmox"} / node_memory_MemTotal_bytes{host="proxmox"})) * 100 > 98'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Proxmox hypervisor memory near exhaustion";
              description = "Hypervisor memory is {{ $value | printf \"%.1f\" }}% used. RAM is nearly gone; the host will swap VM pages or OOM. Shed VM load now.";
            };
          }
          {
            alert = "HardwareMemoryControllerErrors";
            # EDAC/memory-controller error events from rasdaemon. On this dense
            # non-binary DDR5 config, IMC errors are the leading indicator of
            # the memory-stress failure mode from the Sept 4 post-mortem.
            expr = "increase(node_ras_mc_events_total[1h]) > 0";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Memory controller (EDAC) errors on hypervisor";
              description = "rasdaemon recorded {{ $value }} memory-controller error events in 1h. Suspect the IMC/DDR5. Test at JEDEC 5200 MT/s and check `ras-mc-ctl --summary`.";
            };
          }
          {
            alert = "ProxmoxBoardSensorHot";
            # Gigabyte WMI board sensors (VRM/PCH/system). Baseline max ~70°C;
            # >90°C sustained means VRM/board heat soak, the airflow problem
            # called out in the crash post-mortem. Unlabeled sensors, so gate
            # on the hottest one.
            expr = ''max by (host) (node_hwmon_temp_celsius{host="proxmox",chip=~"wmi.*"}) > 90'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Proxmox motherboard/VRM sensor hot";
              description = "A Gigabyte board sensor is {{ $value | printf \"%.0f\" }}°C for 5m. Improve Mini-ITX case exhaust and VRM airflow.";
            };
          }
          {
            alert = "ProxmoxBIOSOutdated";
            # BIOS F6 ships the early Arrow Lake-S microcode implicated in the
            # Sept 4 transient-stability crash. Flash to >= F8. Fires quietly
            # until the board is reflashed.
            expr = ''node_dmi_info{host="proxmox",bios_version="F6"} == 1'';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Proxmox BIOS is on the known-unstable F6";
              description = "The hypervisor is on BIOS F6, which carries early Arrow Lake-S microcode linked to transient VRM/SoC instability. Flash to >= F8 and set the Intel Default power profile: docs/runbooks/proxmox-hardware-crash.md.";
            };
          }
        ];
      }
      {
        name = "sriov-network";
        rules = [
          {
            alert = "SRIOVNetworkPacketDropsHigh";
            expr = ''(rate(node_network_receive_drop_total{device=~"eth0|enp2s0f1np1"}[5m]) + rate(node_network_transmit_drop_total{device=~"eth0|enp2s0f1np1"}[5m])) > 10'';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "High packet drop rate on SR-IOV interface {{ $labels.device }} on {{ $labels.host }}";
              description = "Interface {{ $labels.device }} on {{ $labels.host }} is dropping {{ $value | printf \"%.1f\" }} pkts/sec. Check iavf ring buffer sizes or jumbo frame MTU.";
            };
          }
          {
            alert = "SRIOVPhysicalLinkFlapping";
            expr = ''increase(node_network_carrier_changes_total{device=~"enp2s0.*"}[15m]) > 2'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Physical Intel X710 link flapping on {{ $labels.host }} ({{ $labels.device }})";
              description = "Interface {{ $labels.device }} had {{ $value }} carrier changes in 15 minutes. Check SFP+ transceivers and cable connections.";
            };
          }
          {
            alert = "VMHighCPUSteal";
            expr = ''avg by (host) (rate(node_cpu_seconds_total{mode="steal",host=~"proxmox-.*"}[5m])) * 100 > 15'';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "High CPU steal time on VM {{ $labels.host }}";
              description = "VM {{ $labels.host }} is experiencing {{ $value | printf \"%.1f\" }}% CPU steal time. Hypervisor is overcommitted or competing with host workloads.";
            };
          }
        ];
      }
      {
        name = "gpu-acceleration";
        rules = [
          {
            alert = "IntelGPUDriverHang";
            expr = ''increase(intel_gpu_resets_total{host="proxmox-applications-1"}[5m]) > 0'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Intel Xe GPU driver hang or engine reset on proxmox-applications-1";
              description = "The Intel Xe GPU driver recorded an engine reset. Transcoding or ML workloads may be stalled.";
            };
          }
        ];
      }
      {
        name = "postgres";
        rules = [
          {
            alert = "PostgresTooManyConnections";
            # Requires postgres_exporter
            expr = "sum by (host) (pg_stat_activity_count) / sum by (host) (pg_settings_max_connections) * 100 > 85";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "PostgreSQL connection pool near exhaustion on {{ $labels.host }}";
              description = "Over 85% of max connections are in use. Upstream services may start timing out.";
            };
          }
          {
            alert = "PostgresDeadlocksDetected";
            expr = "increase(pg_stat_database_deadlocks[5m]) > 0";
            for = "1m";
            labels.severity = "warning";
            annotations = {
              summary = "PostgreSQL deadlocks on {{ $labels.host }}";
              description = "Deadlocks detected in the last 5 minutes. Check application queries.";
            };
          }
          {
            alert = "PostgresLowCacheHitRatio";
            # Alerts if the database has to read from disk instead of memory for more than 10% of queries
            expr = ''
              sum by (host) (rate(pg_stat_database_blks_hit[5m])) 
              / 
              (sum by (host) (rate(pg_stat_database_blks_hit[5m])) + sum by (host) (rate(pg_stat_database_blks_read[5m]))) 
              < 0.90
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "PostgreSQL cache hit ratio low on {{ $labels.host }}";
              description = "Cache hit ratio is below 90%. The database is doing excessive disk I/O. Consider increasing shared_buffers.";
            };
          }
        ];
      }
      {
        name = "caddy";
        rules = [
          {
            alert = "CaddyHigh5xxErrorRate";
            # caddy_http_requests_total has no status label. 5xx lives on the
            # duration histogram as code.
            expr = ''
              sum by (host) (rate(caddy_http_request_duration_seconds_count{code=~"5.."}[5m]))
              /
              sum by (host) (rate(caddy_http_request_duration_seconds_count[5m]))
              * 100 > 5
            '';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "High 5xx error rate on Caddy proxy ({{ $labels.host }})";
              description = "Caddy is returning 5xx for {{ printf \"%.1f\" $value }}% of recent requests. Check caddy_reverse_proxy_upstreams_healthy and the upstream journal.";
            };
          }
          {
            alert = "CaddyUpstreamUnhealthy";
            expr = "caddy_reverse_proxy_upstreams_healthy == 0";
            for = "3m";
            labels.severity = "critical";
            annotations = {
              summary = "Caddy upstream {{ $labels.upstream }} is unhealthy on {{ $labels.host }}";
              description = "Caddy on {{ $labels.instance }} marked {{ $labels.upstream }} unhealthy. Edge Caddy will 502 until it recovers.";
            };
          }
          {
            alert = "CaddyRequestErrors";
            expr = "sum by (host) (rate(caddy_http_request_errors_total[5m])) > 0.1";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Caddy is logging request errors on {{ $labels.host }}";
              description = "{{ printf \"%.2f\" $value }} request errors/s on {{ $labels.instance }}. Handler-level failures, not necessarily 5xx responses.";
            };
          }
        ];
      }
      {
        name = "smartctl";
        rules = [
          {
            alert = "SmartctlDeviceUnhealthy";
            expr = "smartctl_device_smart_status == 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "SMART failed on {{ $labels.device }} ({{ $labels.instance }})";
              description = "smartctl reports SMART status 0 for {{ $labels.device }}. Replace or inspect the disk on the hypervisor.";
            };
          }
          {
            alert = "SmartctlCriticalWarning";
            expr = "smartctl_device_critical_warning > 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "NVMe critical warning on {{ $labels.device }}";
              description = "smartctl_device_critical_warning is {{ $value }} on {{ $labels.instance }}. Check `smartctl -a /dev/{{ $labels.device }}`.";
            };
          }
          {
            alert = "SmartctlMediaErrors";
            expr = "increase(smartctl_device_media_errors[1h]) > 0";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "NVMe media errors on {{ $labels.device }}";
              description = "{{ $value | printf \"%.0f\" }} new media errors in 1h on {{ $labels.instance }}.";
            };
          }
          {
            alert = "SmartctlAvailableSpareLow";
            expr = "smartctl_device_available_spare < smartctl_device_available_spare_threshold";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "NVMe spare blocks below threshold on {{ $labels.device }}";
              description = "available_spare is below the device threshold on {{ $labels.instance }}.";
            };
          }
          {
            alert = "SmartctlHighTemperature";
            expr = "smartctl_device_temperature > 70";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Disk {{ $labels.device }} is {{ $value }}°C";
              description = "SMART temperature on {{ $labels.instance }} has been above 70°C for 10m.";
            };
          }
          {
            alert = "SmartctlNvmeWearHigh";
            expr = "smartctl_device_percentage_used > 30";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "NVMe {{ $labels.device }} is {{ $value }}% worn";
              description = "smartctl_device_percentage_used on {{ $labels.instance }} is past 30%. The hypervisor boot disk is DRAM-less and already wrote tens of TB. Plan a replacement before 80%.";
            };
          }
          {
            alert = "SmartctlNvmeWearCritical";
            expr = "smartctl_device_percentage_used > 80";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "NVMe {{ $labels.device }} is {{ $value }}% worn";
              description = "Replace the hypervisor NVMe. Guest roots and pve-root live on this drive's failure domain.";
            };
          }
        ];
      }
      {
        name = "pgbouncer";
        rules = [
          {
            alert = "PgBouncerWaitingClients";
            expr = "sum by (host, database) (pgbouncer_pools_client_waiting_connections) > 0";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "PgBouncer clients waiting for {{ $labels.database }}";
              description = "{{ $value }} clients waiting on {{ $labels.host }}. The pool is the bottleneck, not Postgres max_connections.";
            };
          }
          {
            alert = "PgBouncerPoolNearCapacity";
            # Session and small transaction pools sit full on purpose
            # (Grafana pins 5, Vaultwarden 2). That is not a page until
            # someone is actually waiting for a server.
            expr = ''
              (
                sum by (host, database) (pgbouncer_databases_current_connections)
                /
                clamp_min(sum by (host, database) (pgbouncer_databases_pool_size), 1)
                * 100 > 85
              )
              and
              sum by (host, database) (pgbouncer_pools_client_waiting_connections) > 0
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "PgBouncer pool {{ $labels.database }} is {{ printf \"%.0f\" $value }}% full and clients are waiting";
              description = "current_connections / pool_size on {{ $labels.host }} with waiting clients. Raise pool_size or find the holder.";
            };
          }
          {
            alert = "PgBouncerClientsNearMax";
            expr = ''
              sum by (host) (pgbouncer_client_connections)
              /
              sum by (host) (pgbouncer_config_max_client_connections)
              * 100 > 85
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "PgBouncer client slots above 85% on {{ $labels.host }}";
              description = "{{ printf \"%.0f\" $value }}% of max_client_connections (200) are in use.";
            };
          }
        ];
      }
      {
        name = "redis";
        rules = [
          {
            alert = "RedisDown";
            expr = ''redis_up{job="redis"} == 0'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "Redis exporter reports redis_up=0";
              description = "The oauth2-proxy Redis instance on {{ $labels.instance }} is not responding. SSO sessions live here.";
            };
          }
          {
            alert = "RedisMemoryHigh";
            expr = "redis_memory_used_bytes / redis_memory_max_bytes * 100 > 90";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Redis memory above 90% of maxmemory";
              description = "{{ printf \"%.0f\" $value }}% of maxmemory on {{ $labels.instance }}. allkeys-lru will evict; rejected connections come next.";
            };
          }
          {
            alert = "RedisRejectedConnections";
            expr = "increase(redis_rejected_connections_total[15m]) > 0";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Redis rejected connections on {{ $labels.instance }}";
              description = "{{ $value | printf \"%.0f\" }} rejected connections in 15m. Check maxclients and memory.";
            };
          }
        ];
      }
      {
        name = "gitlab";
        rules = [
          {
            alert = "GitLabRailsErrorRate";
            expr = ''
              sum (rate(gitlab_sli_rails_request_error_total[5m]))
              /
              clamp_min(sum (rate(gitlab_sli_rails_request_total[5m])), 0.01)
              > 0.05
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "GitLab Rails error rate is {{ $value | humanizePercentage }}";
              description = "gitlab_sli_rails_request_error_total / total is above 5% for 10m. Check puma and Sidekiq on proxmox-applications-2.";
            };
          }
          {
            alert = "GitLabSidekiqErrorRate";
            expr = ''
              sum (rate(gitlab_sli_sidekiq_execution_error_total[5m]))
              /
              clamp_min(sum (rate(gitlab_sli_sidekiq_execution_total[5m])), 0.01)
              > 0.05
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "GitLab Sidekiq error rate is {{ $value | humanizePercentage }}";
              description = "Background job executions are failing. Check sidekiq on proxmox-applications-2 and Postgres.";
            };
          }
          {
            alert = "GitLabPumaQueueHigh";
            expr = "sum by (instance) (puma_queued_connections) > 5";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "GitLab Puma request queue is {{ $value }}";
              description = "Requests are waiting for a Puma thread on {{ $labels.instance }}.";
            };
          }
          {
            alert = "GitLabHttp5xxRate";
            expr = ''
              sum (rate(http_requests_total{job="gitlab",status="5xx"}[5m]))
              /
              clamp_min(sum (rate(http_requests_total{job="gitlab"}[5m])), 0.01)
              * 100 > 5
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "GitLab HTTP 5xx rate is {{ printf \"%.1f\" $value }}%";
              description = "http_requests_total status=5xx on the GitLab scrape.";
            };
          }
        ];
      }
      {
        name = "gitlab-runner";
        rules = [
          {
            alert = "GitLabRunnerErrors";
            expr = ''increase(gitlab_runner_errors_total{level=~"error|fatal|panic"}[15m]) > 0'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "GitLab runner {{ $labels.level }} errors on {{ $labels.instance }}";
              description = "{{ $value | printf \"%.0f\" }} {{ $labels.level }} events in 15m. User job failures are gitlab_runner_failed_jobs_total and are not this alert.";
            };
          }
          {
            alert = "GitLabRunnerHealthCheckFailing";
            expr = "increase(gitlab_runner_worker_health_check_failures_total[15m]) > 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "GitLab runner health checks failing on {{ $labels.instance }}";
              description = "The runner cannot talk to GitLab or its executor. CI of record will stall.";
            };
          }
          {
            alert = "GitLabRunnerConfigLoadFailed";
            expr = "increase(gitlab_runner_configuration_loading_error_total[15m]) > 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "GitLab runner failed to load its config";
              description = "configuration_loading_error_total increased on {{ $labels.instance }}. Check gitlab-runner.service and the sops token file.";
            };
          }
        ];
      }
      {
        name = "keycloak";
        rules = [
          {
            alert = "KeycloakServerErrorRate";
            expr = ''
              sum by (instance) (rate(http_server_requests_seconds_count{job="keycloak",outcome="SERVER_ERROR"}[5m]))
              /
              clamp_min(sum by (instance) (rate(http_server_requests_seconds_count{job="keycloak"}[5m])), 0.01)
              > 0.05
            '';
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Keycloak SERVER_ERROR rate is {{ $value | humanizePercentage }} on {{ $labels.instance }}";
              description = "Quarkus http_server_requests_seconds_count outcome=SERVER_ERROR. SSO logins will fail. Check keycloak.service on proxmox-applications-1.";
            };
          }
        ];
      }
      {
        name = "ntfy";
        rules = [
          {
            alert = "NtfyPublishFailures";
            expr = "increase(ntfy_messages_published_failure[15m]) > 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "ntfy is failing to publish on {{ $labels.instance }}";
              description = "{{ $value | printf \"%.0f\" }} publish failures in 15m. Alertmanager pages stop reaching phones if ntfy on proxmox-observability is down.";
            };
          }
          {
            alert = "NtfyHttp5xxRate";
            expr = ''
              sum by (instance) (rate(ntfy_http_requests_total{http_code=~"5.."}[5m]))
              /
              clamp_min(sum by (instance) (rate(ntfy_http_requests_total[5m])), 0.01)
              * 100 > 5
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "ntfy HTTP 5xx rate is {{ printf \"%.1f\" $value }}% on {{ $labels.instance }}";
              description = "ntfy_http_requests_total http_code 5xx. The pager itself is unhealthy.";
            };
          }
        ];
      }
      {
        name = "garage";
        rules = [
          {
            # Single node, RF=1. Unhealthy is a write outage, not
            # degraded-but-serving. TargetDown still covers a scrape failure
            # of :3903/metrics.
            alert = "GarageClusterUnhealthy";
            expr = ''cluster_healthy{job="garage"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage cluster is unhealthy ({{ $labels.host }})";
              description = "cluster_healthy=0 on {{ $labels.instance }}: the layout node is disconnected. Attic/Mimir/Loki will 503 at proxmox-observability:3902. Check garage.service and the tailnet on proxmox-observability.";
            };
          }
          {
            alert = "GarageClusterUnavailable";
            expr = ''cluster_available{job="garage"} == 0'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage cluster cannot serve requests ({{ $labels.host }})";
              description = "cluster_available=0 on {{ $labels.instance }}: at least one partition lacks quorum. S3 reads and writes are failing. Check garage status on proxmox-observability; clients use proxmox-observability:3902.";
            };
          }
          {
            # Garage docs: this should be zero or fall back to zero rapidly.
            # Persistent values are ghost objects (200 then empty body).
            alert = "GarageBlockResyncErrors";
            expr = ''block_resync_errored_blocks{job="garage"} > 0'';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage cannot resync {{ $value }} block(s) on {{ $labels.host }}";
              description = "{{ $value }} block hashes failed to resync. That is likely data loss / ghost objects, not split merkle. Do not garage repair blocks on this cluster. See docs/runbooks/garage-metadata-resync.md (ghost objects).";
            };
          }
          {
            # Split merkle is this fleet's real Garage outage: one
            # node 200s, the other 404s. Merkle updater should drain; a
            # rebuild can take tens of minutes. Page if the queue stays
            # above 100 and is not falling.
            alert = "GarageMerkleTodoStuck";
            expr = ''
              (
                table_merkle_updater_todo_queue_length{job="garage"} > 100
              and
                (
                  table_merkle_updater_todo_queue_length{job="garage"}
                  -
                  table_merkle_updater_todo_queue_length{job="garage"} offset 15m
                ) >= 0
              )
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Garage merkle queue stuck on {{ $labels.host }} ({{ $labels.table_name }})";
              description = "table {{ $labels.table_name }} merkle TODO is {{ $value }} and has not decreased for 30m. Rebuild merkle, then garage repair -a --yes tables. See docs/runbooks/garage-metadata-resync.md. S3 clients stay on proxmox-observability:3902.";
            };
          }
          {
            alert = "GarageDiskSpaceLow";
            expr = ''
              (
                garage_local_disk_avail{job="garage"}
                /
                garage_local_disk_total{job="garage"}
              ) * 100 < 10
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Garage {{ $labels.volume }} volume below 10% on {{ $labels.host }}";
              description = "{{ $labels.volume }} on {{ $labels.instance }} has {{ printf \"%.1f\" $value }}% free. Data is TrueNAS NFS; metadata is local LMDB. Writes fail when either fills.";
            };
          }
          {
            alert = "GarageDiskSpaceCritical";
            expr = ''
              (
                garage_local_disk_avail{job="garage"}
                /
                garage_local_disk_total{job="garage"}
              ) * 100 < 5
            '';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage {{ $labels.volume }} volume below 5% on {{ $labels.host }}";
              description = "{{ $labels.volume }} on {{ $labels.instance }} has {{ printf \"%.1f\" $value }}% free. S3 puts will start failing.";
            };
          }
          {
            # 404s are normal (missing objects). 5xx is quorum, metadata, or
            # NFS. Absolute rate>10/s from upstream examples is too high
            # for this cluster.
            alert = "GarageS3ServerErrorRate";
            expr = ''
              (
                sum by (instance, host) (rate(api_s3_error_counter{job="garage",status_code=~"5.."}[5m]))
                /
                sum by (instance, host) (rate(api_s3_request_counter{job="garage"}[5m]))
              ) * 100 > 5
            '';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Garage S3 5xx rate above 5% on {{ $labels.host }}";
              description = "{{ printf \"%.1f\" $value }}% of S3 requests on {{ $labels.instance }} are 5xx. Check cluster_healthy, the metadata db, and the TrueNAS NFS mounts. Clients use proxmox-observability:3902.";
            };
          }
        ];
      }
      {
        name = "mimir";
        rules = [
          {
            alert = "MimirCompactorFailed";
            # reason=shutdown is the compactor treating context.Canceled as a
            # stop (including ForEachJob cancel when a sibling GET hits a
            # ghost Garage object). Only page on actual compaction errors.
            expr = ''increase(cortex_compactor_runs_failed_total{reason="error"}[1h]) > 0'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir compactor failed on {{ $labels.instance }}";
              description = "Compaction failures stop cleanup from rewriting anonymous/bucket-index.json.gz; Grafana store-gateway queries then fail with err-mimir-bucket-index-too-old.";
            };
          }
          {
            alert = "MimirCompactorHasNotRun";
            expr = "(time() - cortex_compactor_last_successful_run_timestamp_seconds) > 7200";
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir compactor has not completed a run on {{ $labels.instance }}";
              description = "Last successful compaction is more than two hours ago. Check MemoryMax/OOM and Garage /health before raising bucket_index.max_stale_period.";
            };
          }
          {
            # Zero for weeks except during a real ghost-object incident
            # (2026-09-05, 2026-09-08): querier/store-gateway cannot fetch a
            # block the bucket index advertises, usually a Garage object with
            # a holed index or chunks/000001 on every replica. Previously
            # silent until a Grafana query hit err-mimir-store-consistency-check-failed.
            alert = "MimirBlockConsistencyCheckFailing";
            expr = "increase(cortex_querier_blocks_consistency_checks_failed_total[15m]) > 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir block consistency checks are failing on {{ $labels.instance }}";
              description = "err-mimir-store-consistency-check-failed: store-gateway could not fetch one or more blocks. Queries and rule evaluations covering that block's time range fail. Confirm the GET of index/chunks/000001 with s3cli against proxmox-observability:3902; if holed on retry, delete the ULID prefix. Re-upload from /var/lib/mimir/tsdb/anonymous/<ulid>/ if that copy is complete, then restart mimir. See docs/runbooks/garage-metadata-resync.md (Mimir section) and docs/adr/2026-09-05-mimir-delete-lost-blocks.md.";
            };
          }
          # cortex_ingester_local_limits is the cap already divided by the
          # ingester count, so these ratios follow
          # limits.max_global_series_per_user without being edited alongside it.
          # Ratio per ingester, not fleet total, because the cap is enforced
          # locally: an uneven hash shard starves one node while the global
          # total still looks fine (docs/adr/2026-09-05-mimir-series-headroom.md).
          {
            # Nothing watched this until obs-2 sat at exactly its 150000 share
            # for hours. Rejection is silent from Mimir's side: samples come
            # back to the writer as 400 err-mimir-max-series-per-user rather
            # than landing in cortex_discarded_samples_total, and the ruler's
            # own output is rejected with everything else, so alert evaluation
            # degrades at the same moment.
            alert = "MimirTenantSeriesLimitAtCap";
            expr = ''
              (
                max by (instance) (cortex_ingester_memory_series)
              /
                max by (instance) (cortex_ingester_local_limits{limit="max_global_series_per_user"})
              ) >= 0.98
            '';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir ingester {{ $labels.instance }} is at its series limit";
              description = "{{ $value | humanizePercentage }} of this ingester's share of limits.max_global_series_per_user. New series are being rejected with err-mimir-max-series-per-user and the ruler cannot write its own results. Cut cardinality with metric_relabel_configs in services/prometheus.nix, or raise the cap only after checking Mimir RSS against MemoryMax. See docs/services/mimir.md (series cap).";
            };
          }
          {
            alert = "MimirTenantSeriesHeadroomLow";
            expr = ''
              (
                max by (instance) (cortex_ingester_memory_series)
              /
                max by (instance) (cortex_ingester_local_limits{limit="max_global_series_per_user"})
              ) > 0.8
            '';
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir ingester {{ $labels.instance }} is near its series limit";
              description = "{{ $value | humanizePercentage }} of this ingester's share of limits.max_global_series_per_user. Find the growth with topk(20, count by (__name__) ({__name__!=\"\"})) before it reaches the cap and writes start failing. See docs/services/mimir.md (series cap).";
            };
          }
          {
            # ingestion_rate/ingestion_burst_size discards do land here, unlike
            # the series cap. A backlog replay after any Mimir or Garage outage
            # can trip the burst, so this reports lost samples the writer has
            # already given up on.
            alert = "MimirSamplesDiscarded";
            expr = "sum by (reason) (rate(cortex_discarded_samples_total[15m])) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir is discarding samples ({{ $labels.reason }})";
              description = "{{ printf \"%.1f\" $value }} samples/s dropped for reason {{ $labels.reason }}. rate_limited means limits.ingestion_rate or ingestion_burst_size, which a queued remote_write replay can hit even when the steady rate is well under. These samples are gone, not retried.";
            };
          }
        ];
      }
      # Meta-monitoring: the alerts that watch the alerting. Every rule in this
      # file is evaluated by the Mimir ruler, so a ruler that fails, stalls, or
      # cannot reach Alertmanager takes the whole fleet's alerting with it and
      # is silent by construction — a broken rule does not page about itself.
      # These read cortex_prometheus_* / cortex_ruler_*, which the ruler
      # exports and which carry real values, unlike the agent-mode prometheus_*
      # equivalents in the prometheus group.
      #
      # Rule groups shard across the two rulers, so aggregate by rule_group
      # rather than instance: a group moving between nodes is normal and is not
      # an incident.
      {
        name = "mimir-ruler";
        rules = [
          {
            # reason="user" is a rule the ruler could evaluate but could not
            # act on: a bad expression, or a recording-rule result rejected on
            # write. The series cap produces exactly this, which is how 158 of
            # these accumulated in the system group unnoticed.
            # reason="operator" is server-side (query timeout, unavailable
            # store) and points at Mimir or Garage rather than the rule.
            alert = "MimirRulerEvaluationFailing";
            expr = ''
              sum by (rule_group, reason) (
                increase(cortex_prometheus_rule_evaluation_failures_total[15m])
              ) > 0
            '';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir ruler failing to evaluate {{ $labels.rule_group }} ({{ $labels.reason }})";
              description = "{{ printf \"%.0f\" $value }} evaluation failures in 15m. reason=user is the rule or its write: check the expression, and check MimirTenantSeriesLimitAtCap, because a rejected recording-rule write lands here. reason=operator is Mimir or Garage. Alerts in this group are not being evaluated while this fires. See docs/services/mimir.md (ruler meta-monitoring).";
            };
          }
          {
            alert = "MimirRulerMissingEvaluations";
            expr = ''
              sum by (rule_group) (
                increase(cortex_prometheus_rule_group_iterations_missed_total[15m])
              ) > 0
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir ruler skipped evaluations of {{ $labels.rule_group }}";
              description = "{{ printf \"%.0f\" $value }} iterations missed in 15m: the group takes longer to evaluate than its interval, so alerts in it are late and `for` durations stretch. Compare cortex_prometheus_rule_group_last_duration_seconds against cortex_prometheus_rule_group_interval_seconds.";
            };
          }
          {
            # The direct "the rules file is broken" signal: the ruler rejected
            # the file and is running whatever it loaded last, or nothing.
            alert = "MimirRulerConfigReloadFailed";
            expr = "max_over_time(cortex_ruler_config_last_reload_successful[10m]) == 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir ruler on {{ $labels.instance }} cannot load its rules";
              description = "The ruler failed to load /etc/mimir-rules. It is evaluating stale rules or none at all, so this file's alerts may not reflect the deployed config. Read the mimir journal for the parse error.";
            };
          }
          {
            # No rules loaded anywhere. absent() rather than == 0 because the
            # failure mode is the metric disappearing, and a comparison against
            # no data never fires.
            alert = "MimirRulerNoRulesLoaded";
            expr = "absent(cortex_prometheus_rule_group_rules)";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "No Mimir ruler is reporting any loaded rule groups";
              description = "Neither ruler exports cortex_prometheus_rule_group_rules, so fleet alerting is evaluating nothing and almost every other alert here is silent for the wrong reason. Check mimir.service on proxmox-observability and the ruler ring.";
            };
          }
          {
            # Evaluation succeeding while delivery fails is the worst case: the
            # alert fires and nobody is told.
            alert = "MimirRulerNotDeliveringAlerts";
            expr = ''
              sum by (alertmanager) (
                increase(cortex_prometheus_notifications_errors_total[15m])
              ) > 0
            '';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir ruler cannot deliver alerts to {{ $labels.alertmanager }}";
              description = "{{ printf \"%.0f\" $value }} notification errors in 15m. Rules are evaluating and firing but the notification is not reaching Alertmanager, so no ntfy push is sent. Check alertmanager.service on proxmox-observability.";
            };
          }
          {
            alert = "MimirRulerNoAlertmanagers";
            expr = "max_over_time(cortex_prometheus_notifications_alertmanagers_discovered[10m]) == 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Mimir ruler has discovered no Alertmanagers";
              description = "ruler.alertmanager_url resolves to nothing reachable. Alerts will evaluate and fire silently. Unlike the agent-mode Prometheus equivalent, this is a real signal: the ruler is the component that notifies.";
            };
          }
          {
            alert = "MimirRulerWriteRequestsFailing";
            expr = ''
              sum by (reason) (
                increase(cortex_ruler_write_requests_failed_total[15m])
              ) > 0
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Mimir ruler write requests failing ({{ $labels.reason }})";
              description = "{{ printf \"%.0f\" $value }} recording-rule writes failed in 15m. reason=client_error is usually a limit rejection (see MimirTenantSeriesLimitAtCap); reason=server_error is the write path. Recording rules silently stop producing series, so anything querying them reads empty rather than erroring.";
            };
          }
        ];
      }
      {
        name = "truenas";
        rules = [
          {
            # Graphite exporter can scrape fine while TrueNAS has stopped
            # pushing. up{job="truenas_scale"} stays 1 in that case.
            alert = "TrueNASMetricsStale";
            expr = "time() - graphite_last_processed_timestamp_seconds > 300";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "TrueNAS has stopped pushing Graphite metrics";
              description = "No Graphite sample on proxmox-observability:9109 for {{ $value | humanizeDuration }}. Pool and VM alerts below are stale. Check reporting on truenas-scale and graphite_exporter.";
            };
          }
          {
            alert = "TrueNASExporterDown";
            expr = ''up{job="truenas_scale"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "TrueNAS Graphite exporter scrape is down";
              description = "Prometheus cannot scrape proxmox-observability:9108. TrueNAS pool state is invisible until this returns.";
            };
          }
          {
            # One-hot gauges: online=1, degraded/faulted/unavail/offline/removed=0
            # when healthy. Fire on any non-online state flipping to 1.
            alert = "TrueNASZfsPoolNotOnline";
            expr = ''zfs_pool{job="truenas",state!="online"} == 1'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "TrueNAS ZFS pool {{ $labels.pool }} is {{ $labels.state }}";
              description = "Pool {{ $labels.pool }} on {{ $labels.instance }} reported state={{ $labels.state }}. Garage NFS and media live here. Check `zpool status` on truenas-scale.";
            };
          }
          {
            alert = "TrueNASZfsPoolMissingOnline";
            expr = ''
              count by (instance, pool) (zfs_pool{job="truenas"}) > 0
              unless
              count by (instance, pool) (zfs_pool{job="truenas",state="online"} == 1)
            '';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "TrueNAS ZFS pool {{ $labels.pool }} has no online series";
              description = "{{ $labels.pool }} still reports state gauges but none of them is online=1.";
            };
          }
          {
            # Netdata disk_space charts are the OS mounts (_root, _var_log),
            # not /mnt/ssd or /mnt/hdd. Pool *capacity* is not in this feed.
            alert = "TrueNASMemoryLow";
            expr = ''
              physical_memory{job="truenas",kind="used"}
              /
              (
                physical_memory{job="truenas",kind="used"}
                +
                physical_memory{job="truenas",kind="free"}
              ) * 100 > 90
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "TrueNAS free RAM is below 10%";
              description = "used/(used+free) is {{ $value | printf \"%.0f\" }}% on {{ $labels.instance }}. Cached/ARC is excluded on purpose.";
            };
          }
          {
            alert = "TrueNASHighIOWait";
            expr = ''cpu_total{job="truenas",kind="iowait"} > 40'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "TrueNAS iowait is {{ $value | printf \"%.0f\" }}%";
              description = "CPU iowait on {{ $labels.instance }} has been above 40% for 15m. Check pool disks and NFS clients.";
            };
          }
          {
            alert = "TrueNASDiskSaturated";
            expr = ''avg_over_time(disk_utilization{job="truenas"}[15m]) > 90'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "TrueNAS disk {{ $labels.disk }} is saturated";
              description = "{{ $labels.disk }} utilization is {{ $value | printf \"%.0f\" }}% on {{ $labels.instance }}.";
            };
          }
          {
            alert = "TrueNASPrimaryNicDown";
            expr = ''interface_operationstate{job="truenas",interface="enp6s16",state="up"} == 0'';
            for = "2m";
            labels.severity = "critical";
            annotations = {
              summary = "TrueNAS primary NIC enp6s16 is down";
              description = "enp6s16 operstate is not up. NFS and the TrueNAS UI go through this interface.";
            };
          }
          {
            alert = "TrueNASClockUnsynced";
            expr = ''clock_synced{job="truenas"} == 0'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "TrueNAS clock is not synced";
              description = "clock_synced=0 on {{ $labels.instance }}. ZFS and metric timestamps will drift.";
            };
          }
        ];
      }
      {
        name = "loki";
        rules = [
          {
            alert = "LokiTargetDown";
            expr = ''up{job="loki"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Loki scrape is down on {{ $labels.instance }}";
              description = "Prometheus cannot scrape {{ $labels.instance }}. Writes to proxmox-observability:3100 fail while this Loki is down.";
            };
          }
          {
            # Single obs member, RF=1. ACTIVE=0 is a node down. ACTIVE>1 is
            # a leftover rpi4 or retired obs-2 Loki that flooded memberlist.
            alert = "LokiRingWrongSize";
            expr = ''
              max by (name) (loki_ring_members{name=~"ingester|distributor|scheduler|compactor",state="ACTIVE"}) != 1
            '';
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Loki {{ $labels.name }} ring has {{ $value }} ACTIVE members (want 1)";
              description = "Expected exactly proxmox-observability. 0 means Loki is down; >1 is usually a leftover rpi4 or retired obs-2 Loki. See docs/services/loki.md.";
            };
          }
          {
            alert = "LokiRingMemberUnhealthy";
            expr = ''loki_ring_members{state="UNHEALTHY"} > 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Loki {{ $labels.name }} ring has an UNHEALTHY member";
              description = "{{ $labels.instance }} sees {{ $value }} UNHEALTHY {{ $labels.name }} member(s). Check loki.service and tailscale0 gossip on proxmox-observability.";
            };
          }
          {
            alert = "LokiRequestErrors";
            expr = ''
              sum by (instance, route) (rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m]))
              /
              sum by (instance, route) (rate(loki_request_duration_seconds_count[5m]))
              > 0.05
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Loki {{ $labels.route }} is returning 5xx on {{ $labels.instance }}";
              description = "{{ $value | humanizePercentage }} of {{ $labels.route }} requests are 5xx. Check Garage and loki.service on proxmox-observability.";
            };
          }
          {
            alert = "LokiS3Errors";
            # Ratio alone hides List 5xx under a high 200 volume. Also
            # page on a sustained absolute 5xx rate.
            expr = ''
              (
                sum by (instance, operation) (rate(loki_s3_request_duration_seconds_count{status_code=~"5.."}[5m]))
                /
                sum by (instance, operation) (rate(loki_s3_request_duration_seconds_count[5m]))
                > 0.05
              )
              or
              sum by (instance, operation) (rate(loki_s3_request_duration_seconds_count{status_code=~"5.."}[5m])) > 0.5
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Loki S3 {{ $labels.operation }} is failing on {{ $labels.instance }}";
              description = "Garage {{ $labels.operation }} 5xx on {{ $labels.instance }} (ratio above 5% or more than 0.5/s). Chunks and the TSDB index live in the loki bucket.";
            };
          }
          {
            # Only the elected boltdb-shipper compactors export a non-zero
            # last-success timestamp. Use max() so the standby (0) is ignored.
            alert = "LokiCompactorHasNotRun";
            expr = "time() - max(loki_boltdb_shipper_compact_tables_operation_last_successful_run_timestamp_seconds) > 7200";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Loki compactor has not succeeded in 2h";
              description = "max(last successful compact-tables) is {{ $value | humanizeDuration }} ago. Index compaction and retention stall; check loki.service on the obs node where loki_boltdb_shipper_compactor_running=1.";
            };
          }
          {
            alert = "LokiIngesterFlushFailures";
            expr = "increase(loki_ingester_chunks_flush_failures_total[15m]) > 5";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Loki ingester cannot flush chunks on {{ $labels.instance }}";
              description = "{{ $value | printf \"%.0f\" }} chunk flush failures in 15m. Usually Garage 503s or a full WAL. Check loki_ingester_wal_disk_full_failures_total.";
            };
          }
          {
            alert = "LokiWALDiskFull";
            expr = "increase(loki_ingester_wal_disk_full_failures_total[15m]) > 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Loki WAL disk is full on {{ $labels.instance }}";
              description = "Ingester WAL writes are failing because the disk is full. Incoming logs will be dropped.";
            };
          }
          {
            alert = "LokiClientDrops";
            expr = ''
              increase(vector_component_discarded_events_total{component_id="loki"}[15m]) > 0
              or
              increase(vector_component_errors_total{component_id="loki"}[15m]) > 0
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Vector is dropping or failing Loki writes from {{ $labels.host }}";
              description = "{{ $value | printf \"%.0f\" }} discarded events or sink errors in 15m on component_id=loki. Check `systemctl status vector` and Loki `:3100`.";
            };
          }
          {
            alert = "LokiPanic";
            expr = "increase(loki_panic_total[15m]) > 0";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Loki panicked on {{ $labels.instance }}";
              description = "loki_panic_total increased. Check journalctl -u loki.service on that host.";
            };
          }
        ];
      }
      {
        # Vector :9598. Same exclusions as TargetDown (desktops / Pi).
        name = "vector";
        rules = [
          {
            alert = "VectorTargetDown";
            expr = ''up{job="vector",instance!~"gaming.*",instance!~"m3pro.*",instance!~"rpi4.*"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Vector scrape is down on {{ $labels.host }}";
              description = "Prometheus cannot scrape {{ $labels.instance }} :9598. Check `systemctl status vector`, cgroup `memory.events`, and whether Loki backpressure filled the disk buffer.";
            };
          }
        ];
      }
    ];
  };

  # Eval-time rule hygiene.
  #
  # This is deliberately not a promtool derivation: `make lint` and CI both run
  # `nix flake check --all-systems --no-build`, so a derivation would be
  # evaluated and never built, and would look like coverage without being any
  # (the exact trap the agent-mode prometheus_* alerts fell into). These
  # assertions run wherever the config is evaluated. For PromQL and template
  # validation, which does need the binary, run promtool against the built file
  # on a Linux host: `make check-mimir-rules`.
  allRules = lib.concatMap (g: g.rules) rulesData.groups;
  alertRules = lib.filter (r: r ? alert) allRules;
  # Keyed on alertname *plus* severity, not alertname alone. The node-exporter
  # mixin deliberately ships one name at two thresholds — 5% warning and 3%
  # critical for NodeFilesystemAlmostOutOfSpace — and Alertmanager tells those
  # apart by the severity label. A collision on both fields is the real bug:
  # the two rules become indistinguishable in routing and silences.
  alertKeys = map (r: "${r.alert}/${r.labels.severity or "<none>"}") alertRules;
  duplicateAlerts = lib.unique (lib.filter (k: lib.count (m: m == k) alertKeys > 1) alertKeys);

  # services/ntfy-group-webhook.py builds every push from annotations.summary
  # and annotations.description, falling back to the bare alertname. An alert
  # carrying only the older prometheus-operator `message` annotation delivers a
  # title with an empty body, which is how GrafanaRequestsFailing shipped.
  unannotated = map (r: r.alert) (
    lib.filter (
      r:
      let
        a = r.annotations or { };
      in
      !(a ? summary) || !(a ? description)
    ) alertRules
  );

  # `for` is deliberately absent on some upstream alerts
  # (NodeTextFileCollectorScrapeError), so it is not checked.
  problems =
    lib.optional (
      duplicateAlerts != [ ]
    ) "duplicate alertname/severity: ${lib.concatStringsSep ", " duplicateAlerts}"
    ++
      lib.optional (unannotated != [ ])
        "no summary/description, so ntfy would send an empty body: ${lib.concatStringsSep ", " unannotated}";

  rulesFile = settingsFormat.generate "rules.yaml" (
    if problems == [ ] then
      rulesData
    else
      throw "services/mimir-rules.nix: ${lib.concatStringsSep "; " problems}"
  );
in
{
  environment.etc."mimir-rules/anonymous/rules.yaml".source = rulesFile;
}
