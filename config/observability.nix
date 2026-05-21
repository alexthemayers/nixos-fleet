{
  pkgs,
  config,
  lib,
  ...
}:
{

  environment.systemPackages = [ pkgs.iperf3 ];
  services.iperf3 = {
    enable = true;
  };

  services.prometheus.exporters = {

    node = {
      enable = true;
      enabledCollectors = [
        "cpu"
        "diskstats"
        "meminfo"
        "netdev"
        "systemd"
      ];
      port = 9100;
      openFirewall = true;
    };
    systemd.enable = true;
  };

  services.alloy = {
    enable = true;
    configPath = "/etc/alloy/config.alloy";
  };

  # Write the config file
  environment.etc."alloy/config.alloy".text = ''
    loki.relabel "journal" {
      forward_to = [loki.write.local.receiver]
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label  = "syslog_id"
      }
    }

    loki.source.journal "read" {
      forward_to = [loki.relabel.journal.receiver]
      labels     = { job = "systemd-journal", host = "${config.networking.hostName}" }
    }

    loki.write "local" {
      endpoint {
        url = "http://proxmox-observability:3100/loki/api/v1/push"
      }
    }

    prometheus.remote_write "local" {
      endpoint {
        url = "http://proxmox-observability:9090"
      }
    }
  '';
}
