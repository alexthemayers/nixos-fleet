{ config, ... }:
{
  systemd.services.loki.after = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.loki.wants = [
    "tailscaled.service"
    "network-online.target"
  ];
  # 4 GiB VMs cannot also run Grafana, Prometheus, Vector and Mimir if Loki is
  # allowed 2G. Cap so a leak is a Loki restart, not a host OOM.
  systemd.services.loki.serviceConfig.MemoryMax = "768M";
  systemd.services.loki.serviceConfig.MemoryHigh = "640M";
  systemd.services.loki.serviceConfig.Restart = "always";
  # 5s meant a Garage outage produced thousands of restarts an hour and buried
  # every other log on the host. Back off, then give up and page.
  systemd.services.loki.serviceConfig.RestartSec = "30s";
  systemd.services.loki.stopIfChanged = false;
  systemd.services.loki.restartIfChanged = false;
  systemd.services.loki.serviceConfig.TimeoutStartSec = "5min";
  # Compactor/WAL leftovers from root-started runs. Z restores ownership
  # recursively so a one-off chown ExecStartPre is not needed every start.
  systemd.tmpfiles.rules = [
    "d /var/lib/loki/index 0750 loki loki -"
    "d /var/lib/loki/index_cache 0750 loki loki -"
    "d /var/lib/loki/compactor 0750 loki loki -"
    "Z /var/lib/loki/index 0750 loki loki -"
    "Z /var/lib/loki/index_cache 0750 loki loki -"
    "Z /var/lib/loki/compactor 0750 loki loki -"
  ];

  services.loki.extraFlags = [ ];

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      3100 # Loki HTTP
      9095 # Loki gRPC
      7946 # memberlist gossip
    ];
    allowedUDPPorts = [
      7946 # memberlist gossip
    ];
  };

  services.loki = {
    enable = true;
    configuration = {
      # Loki defaults to true. Grafana and Vector do not send X-Scope-OrgID,
      # so Explore/labels and every push returned 401 "no org id". Same
      # single-tenant choice as Mimir (`multitenancy_enabled = false`).
      auth_enabled = false;

      server = {
        log_format = "json";
        grpc_server_max_recv_msg_size = 104857600;
      };

      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };

      storage_config.tsdb_shipper = {
        active_index_directory = "/var/lib/loki/index";
        cache_location = "/var/lib/loki/index_cache";
      };

      schema_config.configs = [
        {
          from = "2024-04-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
      limits_config = {
        retention_period = "1488h"; # 62 days
        ingestion_rate_mb = 16;
        ingestion_burst_size_mb = 32;
      };
    };
  };
}
