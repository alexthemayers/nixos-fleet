{
  config,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets."mimir/s3_access_key" = { };
  sops.secrets."mimir/s3_secret_key" = { };
  sops.templates."mimir.env" = {
    content = ''
      MIMIR_S3_ACCESS_KEY_ID=${config.sops.placeholder."mimir/s3_access_key"}
      MIMIR_S3_SECRET_ACCESS_KEY=${config.sops.placeholder."mimir/s3_secret_key"}
    '';
  };
  systemd.services.mimir.after = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.mimir.wants = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.mimir.serviceConfig.EnvironmentFile = config.sops.templates."mimir.env".path;
  systemd.services.mimir.serviceConfig.ExecStart = lib.mkForce (
    let
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "mimir.yaml" config.services.mimir.configuration;
    in
    "/bin/sh -c '"
    + "TAILSCALE_IP=\"\"; "
    + "while [ -z \"$TAILSCALE_IP\" ]; do "
    + "  TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 | head -n1); "
    + "  if [ -z \"$TAILSCALE_IP\" ]; then sleep 1; fi; "
    + "done; "
    + "export MIMIR_CLUSTER_IP=$TAILSCALE_IP; "
    + "JOIN_OBS=$(${pkgs.tailscale}/bin/tailscale ip -4 proxmox-observability | head -n1); "
    + "export JOIN_OBSERVABILITY=\"\${JOIN_OBS:-proxmox-observability}:7947\"; "
    + "JOIN_RPI=$(${pkgs.tailscale}/bin/tailscale ip -4 rpi4 | head -n1); "
    + "export JOIN_RPI4=\"\${JOIN_RPI:-rpi4}:7947\"; "
    + "exec ${config.services.mimir.package}/bin/mimir "
    + "-config.file=${configFile} "
    + "-config.expand-env=true "
    + "'"
  );
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      9009 # Mimir HTTP
      9096 # Mimir gRPC
      7947 # memberlist gossip
    ];
    allowedUDPPorts = [
      7947 # memberlist gossip
    ];
  };
  services.mimir = {
    enable = true;
    extraFlags = [
      "-config.expand-env=true"
    ];
    configuration = {
      multitenancy_enabled = false;
      target = "all";
      limits = {
        ingestion_rate = 0;
        ingestion_burst_size = 2147483647;
        max_global_series_per_user = 100000000;
        out_of_order_time_window = "1h";
      };
      query_scheduler = {
        max_outstanding_requests_per_tenant = 4096;
      };
      server = {
        http_listen_port = 9009;
        grpc_listen_port = 9096;
        log_format = "json";
        grpc_server_max_recv_msg_size = 104857600;
      };
      blocks_storage = {
        backend = "s3";
        s3 = {
          endpoint = "proxmox-db:3902";
          region = "garage";
          bucket_name = "mimir";
          access_key_id = "\${MIMIR_S3_ACCESS_KEY_ID}";
          secret_access_key = "\${MIMIR_S3_SECRET_ACCESS_KEY}";
          insecure = true;
        };
        tsdb = {
          dir = "/var/lib/mimir/tsdb";
        };
      };
      memberlist = {
        cluster_label = "mimir-cluster";
        node_name = "mimir-${config.networking.hostName}";
        bind_addr = [ "\${MIMIR_CLUSTER_IP}" ];
        bind_port = 7947;
        join_members = [
          "\${JOIN_OBSERVABILITY}"
          "\${JOIN_RPI4}"
        ];
        advertise_addr = "\${MIMIR_CLUSTER_IP}";
        # Faster failure detection and node eviction
        dead_node_reclaim_time = "30s";
        rejoin_interval = "60s";
        leave_timeout = "5s";
        gossip_interval = "10s";
        packet_dial_timeout = "5s";
        retransmit_factor = 3;
        gossip_nodes = 3;
      };
      ingester = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          replication_factor = 2;
          # Ring heartbeat settings
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
          instance_addr = "\${MIMIR_CLUSTER_IP}";
        };
      };
      distributor = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
          instance_addr = "\${MIMIR_CLUSTER_IP}";
        };
      };
      store_gateway = {
        sharding_ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
          instance_addr = "\${MIMIR_CLUSTER_IP}";
        };
      };

      compactor = {
        sharding_ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "60s";
          instance_addr = "\${MIMIR_CLUSTER_IP}";
        };
      };
      querier = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
          instance_addr = "\${MIMIR_CLUSTER_IP}";
        };
      };
    };
  };
}
