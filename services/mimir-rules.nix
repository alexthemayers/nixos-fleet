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
            expr = ''100 - (avg by(host) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High CPU usage on {{ $labels.host }}";
              description = "CPU usage is above 85% for 5 minutes";
            };
          }
          {
            alert = "HighMemoryUsage";
            expr = "(1 - (node_memory_MemAvailable_bytes{host!=\"proxmox\"} / node_memory_MemTotal_bytes{host!=\"proxmox\"})) * 100 > 85";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High memory usage on {{ $labels.host }}";
              description = "Memory usage is above 85% for 5 minutes";
            };
          }
          {
            alert = "LowDiskSpace";
            expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 < 15'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Low disk space on {{ $labels.host }}";
              description = "Disk space is below 15% on {{ $labels.device }}";
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
            expr = ''up{instance!~"gaming.*",instance!~"m3pro.*",instance!~"rpi4.*"} == 0'';
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
                node_filesystem_avail_bytes{fstype!="",mountpoint!=""} / node_filesystem_size_bytes{fstype!="",mountpoint!=""} * 100 < 15
              and
                predict_linear(node_filesystem_avail_bytes{fstype!="",mountpoint!=""}[6h], 24*60*60) < 0
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_avail_bytes{fstype!="",mountpoint!=""} / node_filesystem_size_bytes{fstype!="",mountpoint!=""} * 100 < 10
              and
                predict_linear(node_filesystem_avail_bytes{fstype!="",mountpoint!=""}[6h], 4*60*60) < 0
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_avail_bytes{fstype!="",mountpoint!=""} / node_filesystem_size_bytes{fstype!="",mountpoint!=""} * 100 < 5
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_avail_bytes{fstype!="",mountpoint!=""} / node_filesystem_size_bytes{fstype!="",mountpoint!=""} * 100 < 3
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_files_free{fstype!="",mountpoint!=""} / node_filesystem_files{fstype!="",mountpoint!=""} * 100 < 40
              and
                predict_linear(node_filesystem_files_free{fstype!="",mountpoint!=""}[6h], 24*60*60) < 0
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_files_free{fstype!="",mountpoint!=""} / node_filesystem_files{fstype!="",mountpoint!=""} * 100 < 20
              and
                predict_linear(node_filesystem_files_free{fstype!="",mountpoint!=""}[6h], 4*60*60) < 0
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_files_free{fstype!="",mountpoint!=""} / node_filesystem_files{fstype!="",mountpoint!=""} * 100 < 5
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
                node_filesystem_files_free{fstype!="",mountpoint!=""} / node_filesystem_files{fstype!="",mountpoint!=""} * 100 < 3
              and
                node_filesystem_readonly{fstype!="",mountpoint!=""} == 0
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
            alert = "NodeRAIDDegraded";
            expr = ''node_md_disks_required{device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"} - ignoring (state) (node_md_disks{state="active",device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}) > 0'';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = "RAID array '{{ $labels.device }}' at {{ $labels.instance }} is in degraded state due to one or more disks failures. Number of spare drives is insufficient to fix issue automatically.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/noderaiddegraded";
              summary = "RAID Array is degraded.";
            };
          }
          {
            alert = "NodeRAIDDiskFailure";
            expr = ''node_md_disks{state="failed",device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"} > 0'';
            labels.severity = "warning";
            annotations = {
              description = "At least one device in RAID array at {{ $labels.instance }} failed. Array '{{ $labels.device }}' needs attention and possibly a disk swap.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/noderaiddiskfailure";
              summary = "Failed device in RAID array.";
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
            alert = "NodeCPUHighUsage";
            expr = ''sum without(mode) (avg without (cpu) (rate(node_cpu_seconds_total{mode!~"idle|iowait"}[2m]))) * 100 > 90'';
            for = "15m";
            labels.severity = "info";
            annotations = {
              description = ''CPU usage at {{ $labels.instance }} has been above 90% for the last 15 minutes, is currently at {{ printf "%.2f" $value }}%.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodecpuhighusage";
              summary = "High CPU usage.";
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
            alert = "NodeMemoryHighUtilization";
            # Exclude the proxmox hypervisor — it runs at high memory by design (balloon driver)
            expr = ''100 - (node_memory_MemAvailable_bytes{host!="proxmox"} / node_memory_MemTotal_bytes{host!="proxmox"} * 100) > 90'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Memory is filling up at {{ $labels.instance }}, has been above 90% for the last 15 minutes, is currently at {{ printf "%.2f" $value }}%.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodememoryhighutilization";
              summary = "Host is running out of memory.";
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
            alert = "NodeBondingDegraded";
            expr = "(node_bonding_slaves - node_bonding_active) != 0";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              description = "Bonding interface {{ $labels.master }} on {{ $labels.instance }} is in degraded state due to one or more slave failures.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/node/nodebondingdegraded";
              summary = "Bonding interface is degraded.";
            };
          }
          {
            alert = "HypervisorOOMKills";
            expr = "increase(node_vmstat_oom_kill[5m]) > 0";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              description = "The Proxmox hypervisor {{ $labels.instance }} has executed an OOM kill in the last 5 minutes. A VM or LXC container was likely terminated.";
              summary = "Hypervisor OOM kill detected.";
            };
          }
          {
            alert = "NodeIOWaitHigh";
            expr = ''avg by (instance) (rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100 > 20'';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "I/O wait time on {{ $labels.instance }} is > 20% for 10 minutes. Storage is struggling to keep up with VM workloads.";
              summary = "High I/O wait on hypervisor.";
            };
          }
          {
            alert = "ZFSPoolCapacityHigh";
            expr = ''(node_filesystem_avail_bytes{fstype="zfs"} / node_filesystem_size_bytes{fstype="zfs"}) * 100 < 20'';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = "ZFS pool {{ $labels.mountpoint }} on {{ $labels.instance }} has less than 20% free space. ZFS performance heavily degrades above 80% capacity.";
              summary = "ZFS pool is over 80% capacity.";
            };
          }
          {
            alert = "KSMThrashing";
            expr = "rate(node_ksmd_full_scans_total[5m]) > 0.2";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              description = "KSM (Kernel Samepage Merging) on {{ $labels.instance }} is completing full scans very rapidly. This usually indicates ksmd is burning excessive CPU trying to deduplicate memory.";
              summary = "KSM is scanning aggressively.";
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
          {
            alert = "PrometheusSDRefreshFailure";
            expr = "increase(prometheus_sd_refresh_failures_total[10m]) > 0";
            for = "20m";
            labels.severity = "warning";
            annotations = {
              description = "Prometheus {{$labels.instance}} has failed to refresh SD with mechanism {{$labels.mechanism}}.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheussdrefreshfailure";
              summary = "Failed Prometheus SD refresh.";
            };
          }
          # PrometheusKubernetesListWatchFailures was dropped: there is no
          # Kubernetes service discovery anywhere in this fleet, so
          # prometheus_sd_kubernetes_failures_total is never produced.
          {
            alert = "PrometheusNotificationQueueRunningFull";
            expr = ''
              (
                predict_linear(prometheus_notifications_queue_length[5m], 60 * 30)
              >
                min_over_time(prometheus_notifications_queue_capacity[5m])
              )
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = "Alert notification queue of Prometheus {{$labels.instance}} is running full.";
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusnotificationqueuerunningfull";
              summary = "Prometheus alert notification queue predicted to run full in less than 30m.";
            };
          }
          # Also inert under agent mode: an agent notifies no Alertmanager, so
          # prometheus_notifications_* is never exported. The ruler does the
          # notifying; MimirRulerNotDeliveringAlerts covers it.
          {
            alert = "PrometheusErrorSendingAlertsToSomeAlertmanagers";
            expr = ''
              (
                rate(prometheus_notifications_errors_total[5m])
              /
                rate(prometheus_notifications_sent_total[5m])
              )
              * 100
              > 1
            '';
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''{{ printf "%.1f" $value }}% of alerts sent by Prometheus {{$labels.instance}} to Alertmanager {{$labels.alertmanager}} were affected by errors.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheuserrorsendingalertstosomealertmanagers";
              summary = "More than 1% of alerts sent by Prometheus to a specific Alertmanager were affected by errors.";
            };
          }
          # PrometheusNotConnectedToAlertmanagers intentionally disabled:
          # All Prometheus instances run in --enable-feature=agent mode (remote-write only).
          # Alerting is handled by the Mimir ruler -> alertmanager pipeline, not by Prometheus directly.
          # Agent-mode Prometheus always reports 0 discovered alertmanagers, making this a permanent false positive.
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
          # The next two are inert here, for the same agent-mode reason as
          # PrometheusNotConnectedToAlertmanagers above: an agent evaluates no
          # rules, so /api/v1/rules is empty and
          # prometheus_rule_evaluation_failures_total /
          # prometheus_rule_group_iterations_missed_total are never exported.
          # They cannot fire and they are not coverage. Every rule in this file
          # runs in the Mimir ruler; the equivalents that do have data are
          # MimirRulerEvaluationFailing and MimirRulerMissingEvaluations in the
          # mimir-ruler group. Kept only to stay diffable against the upstream
          # prometheus-operator set.
          {
            alert = "PrometheusRuleFailures";
            expr = "increase(prometheus_rule_evaluation_failures_total[5m]) > 0";
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has failed to evaluate {{ printf "%.0f" $value }} rules in the last 5m.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusrulefailures";
              summary = "Prometheus is failing rule evaluations.";
            };
          }
          {
            alert = "PrometheusMissingRuleEvaluations";
            expr = "increase(prometheus_rule_group_iterations_missed_total[5m]) > 0";
            for = "15m";
            labels.severity = "warning";
            annotations = {
              description = ''Prometheus {{$labels.instance}} has missed {{ printf "%.0f" $value }} rule group evaluations in the last 5m.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusmissingruleevaluations";
              summary = "Prometheus is missing rule evaluations due to slow rule group evaluation.";
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
          {
            alert = "PrometheusErrorSendingAlertsToAnyAlertmanager";
            expr = ''
              min without (alertmanager) (
                rate(prometheus_notifications_errors_total{alertmanager!~""}[5m])
              /
                rate(prometheus_notifications_sent_total{alertmanager!~""}[5m])
              )
              * 100
              > 3
            '';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              description = ''{{ printf "%.1f" $value }}% minimum errors while sending alerts from Prometheus {{$labels.instance}} to any Alertmanager.'';
              runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheuserrorsendingalertstoanyalertmanager";
              summary = "Prometheus encounters more than 3% errors sending alerts to any Alertmanager.";
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
        name = "TLSCertificates";
        rules = [
          {
            alert = "CaddySSLCertExpiringSoon";
            expr = "caddy_tls_certificate_expiry_time_seconds - time() < 86400 * 7";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "SSL Certificate expiring soon on {{ $labels.host }}";
              description = "Certificate for {{ $labels.subject }} expires in less than 7 days. Check Caddy ACME challenges.";
            };
          }
          {
            alert = "CaddyACMEChallengeFailing";
            expr = "increase(caddy_tls_acme_challenge_errors_total[1h]) > 0";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "Caddy ACME challenges are failing on {{ $labels.host }}";
              description = "Caddy cannot renew SSL certificates. Check DNS, port 80/443 forwarding, or rate limits.";
            };
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
            # High DERP traffic usually means NAT traversal failed and you lost direct P2P connections
            expr = "rate(tailscale_derp_io_bytes_total[5m]) > 5000000"; # 5MB/s
            for = "15m";
            labels.severity = "warning";
            annotations = {
              summary = "Heavy DERP relay usage on {{ $labels.tailscale_machine }}";
              description = "P2P connection likely failed. Traffic is falling back to Tailscale DERP relays, which will degrade performance.";
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
            # Alert if a node is actively sending traffic but *only* via DERP (indicating direct P2P failure)
            expr = ''
              rate(tailscaled_outbound_bytes_total{path="derp"}[10m]) > 0
              and
              rate(tailscaled_outbound_bytes_total{path="direct"}[10m]) == 0
            '';
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "Tailscale node {{ $labels.tailscale_machine }} is using DERP relays exclusively";
              description = "No direct P2P connection found. All outbound traffic is routed through DERP relay servers, limiting throughput.";
            };
          }
        ];
      }
      {
        name = "hardware-accelerators";
        rules = [
          {
            alert = "GpuHighTemperature";
            # Requires node_exporter hwmon collector to be enabled for amdgpu/i915/xe
            expr = ''node_hwmon_temp_celsius{sensor=~"amdgpu|i915|xe"} > 85'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "High GPU temperature on {{ $labels.host }}";
              description = "GPU temperature has exceeded 85°C. Check cooling or active workloads.";
            };
          }
          {
            # Renamed from GpuDriverHangDetected: this counter is ECC memory
            # errors from EDAC and says nothing about the GPU driver.
            alert = "CorrectableMemoryErrorsSpiking";
            expr = "increase(node_edac_correctable_errors_total[5m]) > 100";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Correctable memory errors on {{ $labels.host }}";
              description = "Correctable EDAC errors are spiking, which usually precedes a DIMM failure.";
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
        name = "zfs-storage";
        rules = [
          {
            alert = "ZfsPoolDegraded";
            expr = ''node_zfs_zpool_state{state!="online"} > 0'';
            for = "15m";
            labels.severity = "critical";
            annotations = {
              summary = "ZFS pool is degraded on {{ $labels.host }}";
              description = "ZFS pool state is {{ $labels.state }}. Check drives on this host immediately.";
            };
          }
          {
            alert = "ZfsPoolCapacityWarning";
            # Alerts when a ZFS pool hits 90% capacity
            expr = "(node_zfs_zpool_size - node_zfs_zpool_free) / node_zfs_zpool_size * 100 > 90";
            for = "30m";
            labels.severity = "warning";
            annotations = {
              summary = "ZFS pool is almost full on {{ $labels.host }}";
              description = "Pool capacity has exceeded 90%. ZFS performance degrades heavily near 100%.";
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
            # Evaluates if more than 5% of requests over the last 5m resulted in a 5xx error
            expr = ''
              sum by (host) (rate(caddy_http_requests_total{status=~"5.."}[5m])) 
              / 
              sum by (host) (rate(caddy_http_requests_total[5m])) 
              * 100 > 5
            '';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "High 5xx error rate on Caddy proxy ({{ $labels.host }})";
              description = "Caddy is returning 5xx errors for {{ printf \"%.1f\" $value }}% of recent requests. Upstream may be down.";
            };
          }
        ];
      }
      {
        name = "garage";
        rules = [
          {
            # RF=2 over two zones with zone redundancy `maximum`: one db VM
            # down is a write outage, not degraded-but-serving. TargetDown
            # still covers a scrape failure of :3903/metrics.
            alert = "GarageClusterUnhealthy";
            expr = ''cluster_healthy{job="garage"} == 0'';
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage cluster is unhealthy ({{ $labels.host }})";
              description = "cluster_healthy=0 on {{ $labels.instance }}: a layout node is disconnected. Writes need both zones; Attic/Mimir/Loki will 503 at proxmox-lb:3902. Check garage.service and tailnet on proxmox-db-1 and proxmox-db-2.";
            };
          }
          {
            alert = "GarageClusterUnavailable";
            expr = ''cluster_available{job="garage"} == 0'';
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "Garage cluster cannot serve requests ({{ $labels.host }})";
              description = "cluster_available=0 on {{ $labels.instance }}: at least one partition lacks quorum. S3 reads and writes are failing. Check garage status on both db nodes; do not pin clients at a single node.";
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
              description = "table {{ $labels.table_name }} merkle TODO is {{ $value }} and has not decreased for 30m. Split metadata 404s one node at the LB. Rebuild merkle on the source, then garage repair -a --yes tables. See docs/runbooks/garage-metadata-resync.md. Do not pin S3 clients at db-1.";
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
              description = "{{ printf \"%.1f\" $value }}% of S3 requests on {{ $labels.instance }} are 5xx. Check cluster_healthy, the metadata db, and the TrueNAS NFS mounts. Do not pin clients off proxmox-lb:3902.";
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
              description = "Neither ruler exports cortex_prometheus_rule_group_rules, so fleet alerting is evaluating nothing and almost every other alert here is silent for the wrong reason. Check mimir.service on both obs nodes and the ruler ring.";
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
              description = "{{ printf \"%.0f\" $value }} notification errors in 15m. Rules are evaluating and firing but the notification is not reaching Alertmanager, so no ntfy push is sent. Check alertmanager.service on both obs nodes.";
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
    ];
  };

  # Eval-time rule hygiene, on the same throw-on-mismatch pattern as the
  # co-routed-peers check in flake.nix.
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

  # `for` is deliberately absent on some upstream alerts (NodeRAIDDiskFailure,
  # NodeTextFileCollectorScrapeError), so it is not checked.
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
