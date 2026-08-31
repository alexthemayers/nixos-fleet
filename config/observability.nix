{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./network-testing.nix
  ];

  environment.systemPackages = [
    pkgs.iperf3
  ];
  services.iperf3 = {
    enable = true;
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = [
        "systemd"
      ];
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
      ];
      # openFirewall emits an nftables accept with no interface match, which
      # exposes 9100 on the public NIC of the cloud VMs. Scraping is allowed
      # only on tailscale0 via the interface rules below.
      openFirewall = false;
    };
    systemd = {
      enable = true;
      # Off by default upstream; without it systemd_service_restart_total does
      # not exist and a crash-looping unit is invisible to alerting.
      extraFlags = [ "--systemd.collector.enable-restart-count" ];
    };
  };

  # Fleet-wide scrape and probe listeners. Explicit because tailscale0 is not a
  # trusted interface: without these, Prometheus goes dark.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    9100 # node exporter
    9558 # systemd exporter
    9374 # smokeping_prober
    12345 # Alloy
    5201 # iperf3 (on-demand; the coordinated mesh is opt-in)
  ];

  services.alloy = {
    enable = true;
    configPath = "/etc/alloy/config.alloy";
    extraFlags = [ "--server.http.listen-addr=0.0.0.0:12345" ];
  };
  systemd.services.alloy.wants = [ "network-online.target" ];
  systemd.services.alloy.after = [
    "network-online.target"
    "tailscaled.service"
  ];
  # Uncapped Alloy peaked at ~2.2 GiB on the 4 GiB obs VMs and starved Loki/Mimir.
  systemd.services.alloy.serviceConfig.MemoryMax = "512M";
  systemd.services.alloy.serviceConfig.MemoryHigh = "384M";

  # nixpkgs exporter. MagicDNS miss used to fail activation; Restart=always
  # plus after=nss-lookup is enough. Tombstones below still mask the old
  # wait-for-host-smokeping-* units so a switch does not start them.
  services.prometheus.exporters.smokeping = {
    enable = true;
    listenAddress = "0.0.0.0";
    pingInterval = "1s";
    openFirewall = false;
    hosts = config.fleet.inventory.nixosHosts ++ [
      "1.1.1.1"
      "proxmox"
    ];
  };
  systemd.services.prometheus-smokeping-exporter = {
    wants = lib.mkForce [ "network-online.target" ];
    after = lib.mkForce [
      "network-online.target"
      "tailscaled.service"
      "systemd-resolved.service"
      "nss-lookup.target"
    ];
    conflicts = [
      "wait-for-host-smokeping-1-1-1-1.service"
      "wait-for-host-smokeping-proxmox-lb.service"
      "wait-for-host-smokeping-proxmox-dev.service"
      "wait-for-host-smokeping-proxmox-db-1.service"
      "wait-for-host-smokeping-proxmox-db-2.service"
      "wait-for-host-smokeping-proxmox-applications-1.service"
      "wait-for-host-smokeping-proxmox-applications-2.service"
      "wait-for-host-smokeping-proxmox-observability-1.service"
      "wait-for-host-smokeping-proxmox-observability-2.service"
      "wait-for-host-smokeping-rpi4.service"
      "wait-for-host-smokeping-xcloud-caddy.service"
      "wait-for-host-smokeping-xcloud-postgres.service"
      "wait-for-host-smokeping-proxmox.service"
    ];
    serviceConfig.Restart = "always";
    serviceConfig.RestartSec = "10s";
  };

  # Tombstones. The previous generation declared fleet.waitForHost.smokeping-*
  # with wantedBy multi-user.target and made the prober After/Wants every one
  # of them. Dropping those attributes is not enough: during switch, systemd
  # still starts the old oneshot and blocks activation until it exits, and rpi4
  # is often down. enable = false replaces each with a masked unit so switch
  # stops them instead of waiting.
  systemd.services."wait-for-host-smokeping-1-1-1-1".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-lb".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-dev".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-db-1".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-db-2".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-applications-1".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-applications-2".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-observability-1".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox-observability-2".enable = false;
  systemd.services."wait-for-host-smokeping-rpi4".enable = false;
  systemd.services."wait-for-host-smokeping-xcloud-caddy".enable = false;
  systemd.services."wait-for-host-smokeping-xcloud-postgres".enable = false;
  systemd.services."wait-for-host-smokeping-proxmox".enable = false;

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
      forward_to     = [loki.process.clean_journal.receiver]
      relabel_rules  = loki.relabel.journal.rules
      format_as_json = true
      max_age        = "12h"
      labels         = { job = "systemd-journal", host = "${config.networking.hostName}" }
    }

    loki.process "clean_journal" {
      forward_to = [loki.write.local.receiver]

      stage.json {
        expressions = {
          message           = "MESSAGE",
          priority          = "PRIORITY",
          syslog_facility   = "SYSLOG_FACILITY",
          syslog_identifier = "SYSLOG_IDENTIFIER",
          cmdline           = "_CMDLINE",
          comm              = "_COMM",
          exe               = "_EXE",
          gid               = "_GID",
          pid               = "_PID",
          systemd_unit      = "_SYSTEMD_UNIT",
          transport         = "_TRANSPORT",
          uid               = "_UID",
        }
      }

      stage.template {
        source   = "clean_json"
        template = `{"message":{{ toJson .message }}{{ if .priority }},"level":"{{ if eq .priority "0" }}emergency{{ else if eq .priority "1" }}alert{{ else if eq .priority "2" }}critical{{ else if eq .priority "3" }}error{{ else if eq .priority "4" }}warning{{ else if eq .priority "5" }}notice{{ else if eq .priority "6" }}info{{ else if eq .priority "7" }}debug{{ else }}info{{ end }}"{{ end }}{{ if .syslog_facility }},"facility":"{{ if eq .syslog_facility "0" }}kern{{ else if eq .syslog_facility "1" }}user{{ else if eq .syslog_facility "2" }}mail{{ else if eq .syslog_facility "3" }}daemon{{ else if eq .syslog_facility "4" }}auth{{ else if eq .syslog_facility "5" }}syslog{{ else if eq .syslog_facility "6" }}lpr{{ else if eq .syslog_facility "7" }}news{{ else if eq .syslog_facility "8" }}uucp{{ else if eq .syslog_facility "9" }}cron{{ else if eq .syslog_facility "10" }}authpriv{{ else if eq .syslog_facility "11" }}ftp{{ else if eq .syslog_facility "12" }}ntp{{ else if eq .syslog_facility "13" }}security{{ else if eq .syslog_facility "14" }}console{{ else if eq .syslog_facility "15" }}clock{{ else if eq .syslog_facility "16" }}local0{{ else if eq .syslog_facility "17" }}local1{{ else if eq .syslog_facility "18" }}local2{{ else if eq .syslog_facility "19" }}local3{{ else if eq .syslog_facility "20" }}local4{{ else if eq .syslog_facility "21" }}local5{{ else if eq .syslog_facility "22" }}local6{{ else if eq .syslog_facility "23" }}local7{{ else }}unknown{{ end }}"{{ end }}{{ if .syslog_identifier }},"service":{{ toJson .syslog_identifier }}{{ end }}{{ if or .priority .syslog_facility .syslog_identifier .pid .uid .gid }},"syslog":{"present":true{{ if .priority }},"level":"{{ if eq .priority "0" }}emergency{{ else if eq .priority "1" }}alert{{ else if eq .priority "2" }}critical{{ else if eq .priority "3" }}error{{ else if eq .priority "4" }}warning{{ else if eq .priority "5" }}notice{{ else if eq .priority "6" }}info{{ else if eq .priority "7" }}debug{{ else }}info{{ end }}"{{ end }}{{ if .syslog_facility }},"facility":"{{ if eq .syslog_facility "0" }}kern{{ else if eq .syslog_facility "1" }}user{{ else if eq .syslog_facility "2" }}mail{{ else if eq .syslog_facility "3" }}daemon{{ else if eq .syslog_facility "4" }}auth{{ else if eq .syslog_facility "5" }}syslog{{ else if eq .syslog_facility "6" }}lpr{{ else if eq .syslog_facility "7" }}news{{ else if eq .syslog_facility "8" }}uucp{{ else if eq .syslog_facility "9" }}cron{{ else if eq .syslog_facility "10" }}authpriv{{ else if eq .syslog_facility "11" }}ftp{{ else if eq .syslog_facility "12" }}ntp{{ else if eq .syslog_facility "13" }}security{{ else if eq .syslog_facility "14" }}console{{ else if eq .syslog_facility "15" }}clock{{ else if eq .syslog_facility "16" }}local0{{ else if eq .syslog_facility "17" }}local1{{ else if eq .syslog_facility "18" }}local2{{ else if eq .syslog_facility "19" }}local3{{ else if eq .syslog_facility "20" }}local4{{ else if eq .syslog_facility "21" }}local5{{ else if eq .syslog_facility "22" }}local6{{ else if eq .syslog_facility "23" }}local7{{ else }}unknown{{ end }}"{{ end }}{{ if .syslog_identifier }},"identifier":{{ toJson .syslog_identifier }}{{ end }}{{ if .pid }},"pid":{{ toJson .pid }}{{ end }}{{ if .uid }},"uid":{{ toJson .uid }}{{ end }}{{ if .gid }},"gid":{{ toJson .gid }}{{ end }}}{{ end }}{{ if or .cmdline .comm .exe .systemd_unit .transport }},"process":{"present":true{{ if .cmdline }},"cmdline":{{ toJson .cmdline }}{{ end }}{{ if .comm }},"comm":{{ toJson .comm }}{{ end }}{{ if .exe }},"exe":{{ toJson .exe }}{{ end }}{{ if .systemd_unit }},"systemd_unit":{{ toJson .systemd_unit }}{{ end }}{{ if .transport }},"transport":{{ toJson .transport }}{{ end }}}{{ end }}}`
      }

      stage.output {
        source = "clean_json"
      }
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
        url = "http://proxmox-lb:3100/loki/api/v1/push"

        // Without these, a push that fails is dropped immediately.
        retry_on_http_429 = true
        max_backoff_period = "5m"
      }

      // proxmox-lb and Loki are both single points of failure for log
      // ingestion. Buffer to disk so an outage delays journals instead of
      // losing them, which is exactly what happened during the Loki
      // crash-loop: the logs explaining the outage were themselves discarded.
      wal {
        enabled = true
        max_segment_age = "24h"
      }
    }
  '';
}
