{
  pkgs,
  config,
  lib,
  ...
}:
let
  hostName = config.networking.hostName;
  postgresLogs = config.services.postgresql.enable;
  # Shared with the Debian guests and the Proxmox host through config/vector/
  # (docs/services/vector.md). @host@ is the only per-host substitution.
  journalRemap = lib.replaceStrings [ "@host@" ] [ hostName ] (
    builtins.readFile ./vector/journal-remap.vrl
  );
  lokiSinkCommon = builtins.fromJSON (builtins.readFile ./vector/loki-sink.json);
  postgresRemap = ''
    host_name = "${hostName}"
    parsed, err = parse_json(.message)
    if err == null && is_object(parsed) {
      . = parsed
    }
    .job = "postgres"
    .service = "postgres"
    .host = host_name
    .syslog_id = "postgres"
    .syslog_facility = "journal"
  '';
in
{
  imports = [
    ./network-testing.nix
  ];

  fleet.networkTesting.enable = true;

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
        "ethtool"
        # Per NFS export: WRITE/COMMIT/LOOKUP latency, vfs events, timeouts.
        # Off by default in node_exporter 1.12. ~700 series per mount.
        "mountstats"
      ];
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
        "--collector.ethtool.device-include=^eth0$"
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
    9598 # Vector prometheus_exporter
    5201 # iperf3 (on-demand; the coordinated mesh is opt-in)
  ];

  # Journal + postgres JSON → Loki. Vector is Rust; a Loki outage is a disk
  # buffer, not a Go heap. Caps: docs/memory.md.
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      data_dir = "/var/lib/vector";
      sources = {
        journald = {
          type = "journald";
          current_boot_only = false;
          journalctl_path = "${pkgs.systemd}/bin/journalctl";
        };
        internal_metrics = {
          type = "internal_metrics";
        };
      }
      // lib.optionalAttrs postgresLogs {
        postgres = {
          type = "file";
          include = [ "/var/lib/postgresql/17/log/*.json" ];
          ignore_older_secs = 43200;
          read_from = "beginning";
        };
      };
      transforms = {
        journal_remap = {
          type = "remap";
          inputs = [ "journald" ];
          source = journalRemap;
        };
      }
      // lib.optionalAttrs postgresLogs {
        postgres_remap = {
          type = "remap";
          inputs = [ "postgres" ];
          source = postgresRemap;
        };
      };
      sinks = {
        loki = lokiSinkCommon // {
          inputs = [
            "journal_remap"
          ]
          ++ lib.optionals postgresLogs [ "postgres_remap" ];
          endpoint = "http://proxmox-observability-debian:3100";
        };
        prometheus_exporter = {
          type = "prometheus_exporter";
          inputs = [ "internal_metrics" ];
          address = "0.0.0.0:9598";
        };
      };
    };
  };
  systemd.services.vector.wants = [ "network-online.target" ];
  systemd.services.vector.after = [
    "network-online.target"
    "tailscaled.service"
  ];
  systemd.services.vector.serviceConfig.MemoryMax = "256M";
  systemd.services.vector.serviceConfig.MemoryHigh = "192M";

  # nixpkgs exporter. MagicDNS miss used to fail activation; Restart=always
  # plus after=nss-lookup is enough.
  services.prometheus.exporters.smokeping = {
    enable = true;
    listenAddress = "0.0.0.0";
    pingInterval = "1s";
    openFirewall = false;
    hosts = config.fleet.inventory.nixosHosts ++ [
      "1.1.1.1"
      "proxmox"
      "proxmox-applications-debian"
      "proxmox-gitlab-debian"
      "proxmox-observability-debian"
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
    serviceConfig.Restart = "always";
    serviceConfig.RestartSec = "10s";
  };

}
