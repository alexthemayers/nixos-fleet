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
      forward_to = []
 
      // Extract service/job name from systemd unit (stripping suffix like .service, .scope, etc.)
      rule {
        source_labels = ["__journal__systemd_unit"]
        regex         = "(.*)\\.[^.]+"
        target_label  = "service"
      }
 
      rule {
        source_labels = ["__journal__systemd_unit"]
        regex         = "(.*)\\.[^.]+"
        target_label  = "job"
      }
 
      // Fallback to syslog identifier if service/job was not extracted from systemd unit
      rule {
        source_labels = ["service", "__journal_syslog_identifier"]
        regex         = ";(.+)"
        target_label  = "service"
      }
 
      rule {
        source_labels = ["job", "__journal_syslog_identifier"]
        regex         = "systemd-journal;(.+)"
        target_label  = "job"
      }
 
      // Extract syslog identifier
      rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label  = "syslog_id"
      }
 
      // Separate kernel logs
      rule {
        source_labels = ["__journal__transport"]
        regex         = "kernel"
        target_label  = "job"
        replacement   = "kernel"
      }
 
      // Separate authentication / security events (syslog facility 4 is auth, 10 is authpriv)
      rule {
        source_labels = ["__journal_syslog_facility"]
        regex         = "4|10"
        target_label  = "syslog_facility"
        replacement   = "auth"
      }
 
      // Mark audit events from the kernel or syslog
      rule {
        source_labels = ["__journal_syslog_identifier"]
        regex         = "audit"
        target_label  = "syslog_facility"
        replacement   = "audit"
      }
    }

    loki.source.journal "read" {
      forward_to     = [loki.write.local.receiver]
      relabel_rules  = loki.relabel.journal.rules
      format_as_json = true
      labels         = { job = "systemd-journal", host = "${config.networking.hostName}" }
    }

    local.file_match "postgres" {
      path_targets = [{ "__address__" = "localhost", "__path__" = "/var/lib/postgresql/17/log/*.json" }]
    }

    loki.source.file "postgres" {
      targets    = local.file_match.postgres.targets
      forward_to = [loki.relabel.postgres.receiver]
    }

    loki.relabel "postgres" {
      forward_to = [loki.write.local.receiver]

      rule {
        target_label = "service"
        replacement  = "postgres"
      }

      rule {
        target_label = "job"
        replacement  = "postgres"
      }

      rule {
        target_label = "host"
        replacement  = "${config.networking.hostName}"
      }
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
