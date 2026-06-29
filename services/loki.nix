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

  systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki.env".path;

  # Inject Tailscale IP dynamically via Environment Variable
  systemd.services.loki.serviceConfig.ExecStart = lib.mkForce (
    let
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "loki.yaml" config.services.loki.configuration;
    in
    "/bin/sh -c '"
    + "TAILSCALE_IP=$(${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 | ${pkgs.gawk}/bin/awk \"/inet / {print \\$2}\" | cut -d/ -f1); "
    + "export LOKI_CLUSTER_IP=$TAILSCALE_IP; "
    + "exec ${config.services.loki.package}/bin/loki "
    + "-config.file=${configFile} "
    + "-config.expand-env=true "
    + "-memberlist.advertise-addr=$TAILSCALE_IP "
    + "-memberlist.bind-port=7946 "
    + "-memberlist.rejoin-interval=60s "
    + "-memberlist.join=proxmox-observability:7946,rpi4:7946"
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
    extraFlags = [
      "-log.format=json"
      "-config.expand-env=true"
    ];
    configuration = {
      auth_enabled = false;
      server.http_listen_port = 3100;

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
        replication_factor = 1;
        ring = {
          kvstore.store = "memberlist";
          # Ring heartbeat settings
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };

      memberlist = {
        bind_addr = [ "0.0.0.0" ];
        bind_port = 7946;
        join_members = [
          "proxmox-observability:7946"
          "rpi4:7946"
        ];
        # Faster failure detection and node eviction
        dead_node_reclaim_time = "30s";
        leave_timeout = "5s";
        gossip_interval = "2s";
        gossip_nodes = 3;
        retransmit_factor = 2;
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
