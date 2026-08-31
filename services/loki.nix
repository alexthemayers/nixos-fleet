{ config, ... }:
{
  sops.secrets."loki/s3_access_key" = { };
  sops.secrets."loki/s3_secret_key" = { };

  # Loki reads these via environmentFile, so a rotated S3 key only takes effect
  # if something restarts the unit. See the same note in services/garage.nix.
  sops.templates."loki.env" = {
    restartUnits = [ "loki.service" ];
    content = ''
      LOKI_S3_ACCESS_KEY_ID=${config.sops.placeholder."loki/s3_access_key"}
      LOKI_S3_SECRET_ACCESS_KEY=${config.sops.placeholder."loki/s3_secret_key"}
    '';
  };

  fleet.waitFor.garage.loki.forServices = [ "loki.service" ];

  fleet.clusterEnv.loki = {
    service = "loki.service";
    ipVariable = "LOKI_CLUSTER_IP";
    extra = {
      JOIN_OBSERVABILITY_1 = "proxmox-observability-1.bee-phrygian.ts.net:7946";
      JOIN_OBSERVABILITY_2 = "proxmox-observability-2.bee-phrygian.ts.net:7946";
    };
  };

  systemd.services.loki.after = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.loki.wants = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.loki.serviceConfig.EnvironmentFile = [
    config.sops.templates."loki.env".path
  ];
  # 4 GiB VMs cannot also run Grafana, Prometheus, Alloy and Mimir if Loki is
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

  services.loki.extraFlags = [
    "-config.expand-env=true"
    # Query frontend ignores common.ring.instance_* and defaults to eth0/en0.
    "-frontend.instance-interface-names=tailscale0"
  ];

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
      # Loki defaults to true. Grafana and Alloy do not send X-Scope-OrgID,
      # so Explore/labels and every push returned 401 "no org id". Same
      # single-tenant choice as Mimir (`multitenancy_enabled = false`).
      auth_enabled = false;

      server = {
        log_format = "json";
        grpc_server_max_recv_msg_size = 104857600;
      };

      # common.ring.instance_* is only the hash ring. The query frontend still
      # picks eth0 (192.168.3.x) and tells queriers to dial that for gRPC. 9095
      # is firewalled to tailscale0, so Grafana labels/Explore hang.
      frontend = {
        address = "\${LOKI_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
      };

      ingester = {
        autoforget_unhealthy = true;
      };

      common = {
        path_prefix = "/var/lib/loki";
        storage.s3 = {
          endpoint = "proxmox-lb:3902";
          region = "garage";
          bucketnames = "loki";
          access_key_id = "\${LOKI_S3_ACCESS_KEY_ID}";
          secret_access_key = "\${LOKI_S3_SECRET_ACCESS_KEY}";
          insecure = true;
          s3forcepathstyle = true;
        };
        # Two ingesters. RF=2 required both to ack, so one obs node down stopped
        # all ingest. RF=1 keeps writes flowing; Garage already stores two copies.
        replication_factor = 1;
        ring = {
          kvstore.store = "memberlist";
          instance_addr = "\${LOKI_CLUSTER_IP}";
          instance_interface_names = [ "tailscale0" ];
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
        };
      };

      memberlist = {
        cluster_label = "loki-cluster";
        node_name = "loki-v4-${config.networking.hostName}";
        bind_addr = [ "\${LOKI_CLUSTER_IP}" ];
        bind_port = 7946;
        join_members = [
          "\${JOIN_OBSERVABILITY_1}"
          "\${JOIN_OBSERVABILITY_2}"
        ];
        advertise_addr = "\${LOKI_CLUSTER_IP}";
        advertise_port = 7946;
        rejoin_interval = "30s";
        dead_node_reclaim_time = "30s";
        leave_timeout = "5s";
        gossip_interval = "10s";
        packet_dial_timeout = "5s";
        retransmit_factor = 3;
        gossip_nodes = 3;
      };

      storage_config.tsdb_shipper = {
        active_index_directory = "/var/lib/loki/index";
        cache_location = "/var/lib/loki/index_cache";
      };

      schema_config.configs = [
        {
          from = "2024-04-01";
          store = "tsdb";
          object_store = "s3";
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
        delete_request_store = "s3";
      };
      limits_config = {
        retention_period = "744h"; # 31 days
        ingestion_rate_mb = 16;
        ingestion_burst_size_mb = 32;
      };
    };
  };
}
