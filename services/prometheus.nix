{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.users.alertmanager = {
    isSystemUser = true;
    group = "alertmanager";
  };
  users.groups.alertmanager = { };
  systemd.services.alertmanager.serviceConfig.User = "alertmanager";
  systemd.services.alertmanager.serviceConfig.Group = "alertmanager";

  sops.secrets."alertmanager/discord_webhook_url" = {
    owner = config.systemd.services.alertmanager.serviceConfig.User;
    group = config.systemd.services.alertmanager.serviceConfig.Group;
  };

  services.prometheus = {
    enable = true;
    port = 9090;

    globalConfig.scrape_interval = "5s";
    scrapeConfigs = [
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [
              "xcloud-caddy:2019"
            ];
          }
        ];
      }
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [
              "proxmox-observability:9090"
            ];
          }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = [
              "xcloud-postgres:9187"
            ];
          }
        ];
      }
      {
        job_name = "systemd exporter";
        static_configs = [
          {
            targets = [
              "proxmox:9558"
              "rpi4:9558"
              "gaming:9558"
              "proxmox-observability:9558"
              "proxmox-video:9558"
              "proxmox-gaming:9558"
              "proxmox-gitlab:9558"
              "xcloud-caddy:9558"
              "xcloud-postgres:9558"
            ];
          }
        ];
      }
      {
        job_name = "node exporter";
        static_configs = [
          {
            targets = [
              "m3pro:9100"
              "proxmox:9100"
              "rpi4:9100"
              "gaming:9100"
              "proxmox-observability:9100"
              "proxmox-video:9100"
              "proxmox-gaming:9100"
              "proxmox-gitlab:9100"
              "xcloud-caddy:9100"
              "xcloud-postgres:9100"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "tailscale exporter";
        static_configs = [
          {
            targets = [
              "proxmox-observability:9250"
            ];
          }
        ];
      }
      {
        job_name = "tailscale-client-metrics";
        static_configs = [
          #          {
          #            targets = [
          #              "m3pro:9251"
          #            ];
          #            labels = {
          #              tailscale_machine = "m3pro";
          #            };
          #          }
          #          {
          #            targets = [
          #              "proxmox:9251"
          #            ];
          #            labels = {
          #              tailscale_machine = "proxmox";
          #            };
          #          }
          {
            targets = [
              "rpi4:9251"
            ];
            labels = {
              tailscale_machine = "rpi4";
            };
          }
          {
            targets = [
              "gaming:9251"
            ];
            labels = {
              tailscale_machine = "gaming";
            };
          }
          {
            targets = [
              "proxmox-video:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-video";
            };
          }
          {
            targets = [
              "proxmox-observability:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-observability";
            };
          }
          {
            targets = [
              "proxmox-gaming:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-gaming";
            };
          }
          {
            targets = [
              "proxmox-gitlab:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-gitlab";
            };
          }
          {
            targets = [
              "xcloud-caddy:9251"
            ];
            labels = {
              tailscale_machine = "xcloud-caddy";
            };
          }
          {
            targets = [
              "xcloud-postgres:9251"
            ];
            labels = {
              tailscale_machine = "xcloud-postgres";
            };
          }
        ];
      }
      {
        job_name = "grafana";
        static_configs = [
          {
            targets = [ "proxmox-observability:3000" ];
          }
        ];
      }
    ];

    # Default alert rules
    rules = [
      (builtins.toJSON {
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
                expr = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85";
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
                expr = ''up{instance!~"gaming.*",instance!~"m3pro.*"} == 0'';
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
                expr = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 90";
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
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} has failed to reload its configuration.";
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
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} has failed to refresh SD with mechanism {{$labels.mechanism}}.";
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheussdrefreshfailure";
                  summary = "Failed Prometheus SD refresh.";
                };
              }
              {
                alert = "PrometheusKubernetesListWatchFailures";
                expr = "increase(prometheus_sd_kubernetes_failures_total[5m]) > 0";
                for = "15m";
                labels.severity = "warning";
                annotations = {
                  description = ''Kubernetes service discovery of Prometheus {{$labels.namespace}}/{{$labels.pod}} is experiencing {{ printf "%.0f" $value }} failures with LIST/WATCH requests to the Kubernetes API in the last 5 minutes.'';
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheuskuberneteslistwatchfailures";
                  summary = "Requests in Kubernetes SD are failing.";
                };
              }
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
                  description = "Alert notification queue of Prometheus {{$labels.namespace}}/{{$labels.pod}} is running full.";
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusnotificationqueuerunningfull";
                  summary = "Prometheus alert notification queue predicted to run full in less than 30m.";
                };
              }
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
                  description = ''{{ printf "%.1f" $value }}% of alerts sent by Prometheus {{$labels.namespace}}/{{$labels.pod}} to Alertmanager {{$labels.alertmanager}} were affected by errors.'';
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheuserrorsendingalertstosomealertmanagers";
                  summary = "More than 1% of alerts sent by Prometheus to a specific Alertmanager were affected by errors.";
                };
              }
              {
                alert = "PrometheusNotConnectedToAlertmanagers";
                expr = "max_over_time(prometheus_notifications_alertmanagers_discovered[5m]) < 1";
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} is not connected to any Alertmanagers.";
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusnotconnectedtoalertmanagers";
                  summary = "Prometheus is not connected to any Alertmanagers.";
                };
              }
              {
                alert = "PrometheusTSDBReloadsFailing";
                expr = "increase(prometheus_tsdb_reloads_failures_total[3h]) > 0";
                for = "4h";
                labels.severity = "warning";
                annotations = {
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} has detected {{$value | humanize}} reload failures over the last 3h.";
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
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} has detected {{$value | humanize}} compaction failures over the last 3h.";
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
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} is not ingesting samples.";
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} is dropping {{ printf "%.4g" $value }} samples/s with different values but duplicated timestamp.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} is dropping {{ printf "%.4g" $value }} samples/s with timestamps arriving out of order.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} failed to send {{ printf "%.1f" $value }}% of the samples to {{ $labels.remote_name}}:{{ $labels.url }}'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} remote write is {{ printf "%.1f" $value }}s behind for {{ $labels.remote_name}}:{{ $labels.url }}.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} remote write desired shards calculation wants to run {{ $value }} shards for queue {{ $labels.remote_name}}:{{ $labels.url }}, which is more than the max of {{ printf `prometheus_remote_storage_shards_max{instance="%s"}` $labels.instance | query | first | value }}.'';
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheusremotewritedesiredshards";
                  summary = "Prometheus remote write desired shards calculation wants to run more than configured max shards.";
                };
              }
              {
                alert = "PrometheusRuleFailures";
                expr = "increase(prometheus_rule_evaluation_failures_total[5m]) > 0";
                for = "15m";
                labels.severity = "critical";
                annotations = {
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has failed to evaluate {{ printf "%.0f" $value }} rules in the last 5m.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has missed {{ printf "%.0f" $value }} rule group evaluations in the last 5m.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has dropped {{ printf "%.0f" $value }} targets because the number of targets exceeded the configured target_limit.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has dropped {{ printf "%.0f" $value }} targets because some samples exceeded the configured label_limit, label_name_length_limit or label_value_length_limit.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has failed {{ printf "%.0f" $value }} scrapes in the last 5m because some targets exceeded the configured body_size_limit.'';
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
                  description = ''Prometheus {{$labels.namespace}}/{{$labels.pod}} has failed {{ printf "%.0f" $value }} scrapes in the last 5m because some targets exceeded the configured sample_limit.'';
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
                  description = ''{{ printf "%.0f" $value }} targets in Prometheus {{$labels.namespace}}/{{$labels.pod}} have failed to sync because invalid configuration was supplied.'';
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
                  description = "Prometheus {{$labels.namespace}}/{{$labels.pod}} query API has less than 20% available capacity in its query engine for the last 15 minutes.";
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
                  description = ''{{ printf "%.1f" $value }}% minimum errors while sending alerts from Prometheus {{$labels.namespace}}/{{$labels.pod}} to any Alertmanager.'';
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
                  100 * sum without (status_code) (namespace_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m{handler!~"/api/datasources/proxy/:id.*|/api/ds/query|/api/tsdb/query", status_code=~"5.."})
                  /
                  sum without (status_code) (namespace_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m{handler!~"/api/datasources/proxy/:id.*|/api/ds/query|/api/tsdb/query"})
                  > 50
                '';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  message = "{{ $labels.namespace }}/{{ $labels.job }}/{{ $labels.handler }} is experiencing {{ $value | humanize }}% errors";
                  runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/grafana/grafanarequestsfailing";
                };
              }
            ];
          }
          {
            name = "grafana_rules";
            rules = [
              {
                record = "namespace_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m";
                expr = "sum by (namespace, job, handler, status_code) (rate(grafana_http_request_duration_seconds_count[5m]))";
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
                expr = ''up{job="tailscale-client-metrics",instance!~"gaming.*",instance!~"m3pro.*"} == 0'';
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
                alert = "GpuDriverHangDetected";
                # Catch instances where the kernel logs a GPU hang (often exposed via dmesg exporter or systemd logs)
                expr = "increase(node_edac_correctable_errors_total[5m]) > 100";
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Hardware errors detected on {{ $labels.host }}";
                  description = "Correctable EDAC errors spiking. This often precedes a GPU driver crash or memory failure.";
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
              {
                alert = "NixOSConfigurationFailed";
                # Helpful for tracking if an automated or remote deploy failed
                expr = ''systemd_unit_state{name="nixos-upgrade.service", state="failed"} == 1'';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "NixOS Upgrade failed on {{ $labels.host }}";
                  description = "The last nixos-rebuild or system upgrade failed. Review the journal for derivation errors.";
                };
              }
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
                  sum(rate(pg_stat_database_blks_hit[5m])) 
                  / 
                  (sum(rate(pg_stat_database_blks_hit[5m])) + sum(rate(pg_stat_database_blks_read[5m]))) 
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
        ];
      })
    ];
    alertmanagers = [
      {
        static_configs = [
          {
            targets = [ "localhost:9093" ];
          }
        ];
      }
    ];
    alertmanager = {
      enable = true;
      listenAddress = "0.0.0.0";

      configuration = {
        route = {
          receiver = "discord-homelab";
          group_by = [
            "alertname"
            "host"
            "job"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
        };
        receivers = [
          {
            name = "discord-homelab";
            discord_configs = [
              {
                webhook_url_file = config.sops.secrets."alertmanager/discord_webhook_url".path;
                send_resolved = true;
                title = ''{{ template "discord.default.title" . }}'';
                message = ''{{ template "discord.default.message" . }}'';
              }
            ];
          }
        ];
      };
    };
  };
}
