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
  systemd.services.mimir.serviceConfig.EnvironmentFile = config.sops.templates."mimir.env".path;
  systemd.services.mimir.serviceConfig.ExecStart = lib.mkForce (
    let
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "mimir.yaml" config.services.mimir.configuration;
    in
    "/bin/sh -c '"
    + "TAILSCALE_IP=$(${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 | ${pkgs.gawk}/bin/awk \"/inet / {print \\$2}\" | cut -d/ -f1); "
    + "exec ${config.services.mimir.package}/bin/mimir "
    + "-config.file=${configFile} "
    + "-config.expand-env=true "
    + "-memberlist.advertise-addr=$TAILSCALE_IP "
    + "-memberlist.advertise-port=7947 "
    + "-memberlist.bind-port=7947 "
    + "-memberlist.join=proxmox-observability:7947,rpi4:7947 "
    + "-ingester.ring.instance-addr=$TAILSCALE_IP "
    + "-store-gateway.sharding-ring.instance-addr=$TAILSCALE_IP "
    + "-compactor.ring.instance-addr=$TAILSCALE_IP "
    + "-distributor.ring.instance-addr=$TAILSCALE_IP "
    + "-querier.ring.instance-addr=$TAILSCALE_IP"
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
      };
      server = {
        http_listen_port = 9009;
        grpc_listen_port = 9096;
        log_format = "json";
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
        bind_addr = [ "0.0.0.0" ];
        bind_port = 7947;
        join_members = [
          "proxmox-observability:7947"
          "rpi4:7947"
        ];
        # Faster failure detection and node eviction
        dead_node_reclaim_time = "30s";
        leave_timeout = "5s";
        gossip_interval = "2s";
        gossip_nodes = 3;
        retransmit_factor = 2;
      };
      ingester = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          replication_factor = 1;
          # Ring heartbeat settings
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };
      distributor = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };
      store_gateway = {
        sharding_ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };
      compactor = {
        sharding_ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };
      querier = {
        ring = {
          kvstore = {
            store = "memberlist";
          };
          heartbeat_period = "5s";
          heartbeat_timeout = "15s";
        };
      };
    };
  };
}
