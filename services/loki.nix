{
  pkgs,
  config,
  lib,
  ...
}:
{
  sops.secrets."loki/s3_access_key" = { };
  sops.secrets."loki/s3_secret_key" = { };

  sops.templates."loki.env" = {
    content = ''
      LOKI_S3_ACCESS_KEY_ID=${config.sops.placeholder."loki/s3_access_key"}
      LOKI_S3_SECRET_ACCESS_KEY=${config.sops.placeholder."loki/s3_secret_key"}
    '';
  };

  systemd.services.loki.after = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.loki.wants = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki.env".path;

  # Inject Tailscale IP dynamically via Environment Variable
  systemd.services.loki.serviceConfig.ExecStart = lib.mkForce (
    let
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "loki.yaml" config.services.loki.configuration;
    in
    "/bin/sh -c '"
    + "TAILSCALE_IP=\"\"; "
    + "while [ -z \"$TAILSCALE_IP\" ]; do "
    + "  TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 | head -n1); "
    + "  if [ -z \"$TAILSCALE_IP\" ]; then sleep 1; fi; "
    + "done; "
    + "export LOKI_CLUSTER_IP=$TAILSCALE_IP; "
    + "JOIN_OBS=$(${pkgs.tailscale}/bin/tailscale ip -4 proxmox-observability | head -n1); "
    + "export JOIN_OBSERVABILITY=\"\${JOIN_OBS:-proxmox-observability}:7946\"; "
    + "JOIN_RPI=$(${pkgs.tailscale}/bin/tailscale ip -4 rpi4 | head -n1); "
    + "export JOIN_RPI4=\"\${JOIN_RPI:-rpi4}:7946\"; "
    + "exec ${config.services.loki.package}/bin/loki "
    + "-config.file=${configFile} "
    + "-config.expand-env=true "
    + "'"
  );

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
      auth_enabled = false;
      server = {
        http_listen_port = 3100;
        grpc_listen_port = 9095;
        log_format = "json";
        grpc_server_max_recv_msg_size = 104857600;
      };

      common = {
        instance_addr = "\${LOKI_CLUSTER_IP}";
        path_prefix = "/var/lib/loki";
        storage.s3 = {
          endpoint = "proxmox-db:3902";
          region = "garage";
          bucketnames = "loki";
          access_key_id = "\${LOKI_S3_ACCESS_KEY_ID}";
          secret_access_key = "\${LOKI_S3_SECRET_ACCESS_KEY}";
          insecure = true;
          s3forcepathstyle = true;
        };
        replication_factor = 2;
        ring = {
          kvstore.store = "memberlist";
          # Ring heartbeat settings
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
        };
      };

      memberlist = {
        cluster_label = "loki-cluster";
        node_name = "loki-${config.networking.hostName}";
        bind_addr = [ "\${LOKI_CLUSTER_IP}" ];
        bind_port = 7946;
        join_members = [
          "\${JOIN_OBSERVABILITY}"
          "\${JOIN_RPI4}"
        ];
        advertise_addr = "\${LOKI_CLUSTER_IP}";
        # Faster failure detection and node eviction
        rejoin_interval = "60s";
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
