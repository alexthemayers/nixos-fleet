{
  pkgs,
  config,
  lib,
  ...
}:
let
  hostName = config.networking.hostName;
  postgresLogs = config.services.postgresql.enable;
  journalRemap = ''
    ts = .timestamp
    # Loki unordered writes reject entries older than ~2h. First-start
    # journal catch-up (audit especially) 400s the ingester and stalls
    # /ready. Drop those here; journald still has them.
    ts_unix, tserr = to_unix_timestamp(ts)
    now_unix = to_unix_timestamp(now())
    if tserr == null && now_unix - ts_unix > 3600 {
      abort
    }
    host_name = "${hostName}"
    message = string(.message) ?? ""
    unit = string(._SYSTEMD_UNIT) ?? ""
    ident = string(.SYSLOG_IDENTIFIER) ?? ""
    transport = string(._TRANSPORT) ?? ""
    priority_raw = string(.PRIORITY) ?? ""
    facility_raw = string(.SYSLOG_FACILITY) ?? ""

    service = ""
    if unit != "" {
      service = replace(unit, r'\.[^.]+$', "")
    } else if ident != "" {
      service = ident
    }
    if service == "" {
      service = "unknown"
    }

    job = "systemd-journal"
    if unit != "" {
      job = service
    } else if ident != "" {
      job = ident
    }
    if transport == "kernel" {
      job = "kernel"
    }

    syslog_id = ident
    if syslog_id == "" {
      syslog_id = service
    }

    syslog_facility_label = "journal"
    if facility_raw == "4" || facility_raw == "10" {
      syslog_facility_label = "auth"
    }
    if ident == "audit" {
      syslog_facility_label = "audit"
    }

    levels = ["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"]
    facilities = ["kern", "user", "mail", "daemon", "auth", "syslog", "lpr", "news", "uucp", "cron", "authpriv", "ftp", "ntp", "security", "console", "clock", "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7"]

    level = "info"
    pri, perr = to_int(priority_raw)
    if perr == null && pri >= 0 && pri <= 7 {
      level = get(levels, [pri]) ?? "info"
    }

    facility_name = null
    fac, ferr = to_int(facility_raw)
    if ferr == null && fac >= 0 && fac <= 23 {
      facility_name = get(facilities, [fac]) ?? null
    }

    syslog = { "present": true, "level": level }
    if facility_name != null {
      syslog.facility = facility_name
    }
    if ident != "" {
      syslog.identifier = ident
    }
    if exists(._PID) {
      syslog.pid = ._PID
    }
    if exists(._UID) {
      syslog.uid = ._UID
    }
    if exists(._GID) {
      syslog.gid = ._GID
    }

    process = null
    if exists(._CMDLINE) || exists(._COMM) || exists(._EXE) || unit != "" || transport != "" {
      process = { "present": true }
      if exists(._CMDLINE) {
        process.cmdline = ._CMDLINE
      }
      if exists(._COMM) {
        process.comm = ._COMM
      }
      if exists(._EXE) {
        process.exe = ._EXE
      }
      if unit != "" {
        process.systemd_unit = unit
      }
      if transport != "" {
        process.transport = transport
      }
    }

    event = {
      "message": message,
      "level": level,
      "job": job,
      "host": host_name,
      "service": service,
      "syslog_id": syslog_id,
      "syslog_facility": syslog_facility_label,
      "syslog": syslog,
    }
    if facility_name != null {
      event.facility = facility_name
    }
    if process != null {
      event.process = process
    }
    event.timestamp = ts
    . = event
  '';
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
        loki = {
          type = "loki";
          inputs = [
            "journal_remap"
          ]
          ++ lib.optionals postgresLogs [ "postgres_remap" ];
          endpoint = "http://proxmox-observability:3100";
          # Disk buffer exists so Loki can be down. Do not fail Vector
          # startup (or `vector validate`) on a /ready timeout.
          healthcheck = {
            enabled = false;
          };
          encoding = {
            codec = "json";
          };
          out_of_order_action = "accept";
          remove_label_fields = true;
          # Labels are fully event-driven (job/host/service). Vector 0.57
          # refuses templates with no static prefix unless this is set.
          dangerously_allow_unconfined_template_resolution = true;
          labels = {
            job = "{{ job }}";
            host = "{{ host }}";
            service = "{{ service }}";
            syslog_id = "{{ syslog_id }}";
            syslog_facility = "{{ syslog_facility }}";
          };
          # Loki is a SPOF for ingest. Disk buffer + block so a push failure
          # stalls the journal cursor instead of dropping lines (the journal
          # itself retains until SystemMaxUse). min disk buffer is 256 MiB.
          buffer = {
            type = "disk";
            max_size = 268435488;
            when_full = "block";
          };
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
}
