{ config, ... }:
{
  imports = [ ./mimir-rules.nix ];
  sops.secrets."mimir/s3_access_key" = { };
  sops.secrets."mimir/s3_secret_key" = { };
  sops.templates."mimir.env" = {
    restartUnits = [ "mimir.service" ];
    content = ''
      MIMIR_S3_ACCESS_KEY_ID=${config.sops.placeholder."mimir/s3_access_key"}
      MIMIR_S3_SECRET_ACCESS_KEY=${config.sops.placeholder."mimir/s3_secret_key"}
    '';
  };

  fleet.waitFor.garage.mimir.forServices = [ "mimir.service" ];

  fleet.clusterEnv.mimir = {
    service = "mimir.service";
    ipVariable = "MIMIR_CLUSTER_IP";
    extra = {
      JOIN_OBSERVABILITY_1 = "proxmox-observability-1.bee-phrygian.ts.net:7947";
      JOIN_OBSERVABILITY_2 = "proxmox-observability-2.bee-phrygian.ts.net:7947";
    };
  };

  systemd.services.mimir.after = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.mimir.wants = [
    "tailscaled.service"
    "network-online.target"
  ];
  systemd.services.mimir.serviceConfig.EnvironmentFile = [
    config.sops.templates."mimir.env".path
  ];
  systemd.services.mimir.serviceConfig.MemoryMax = "2.5G";
  systemd.services.mimir.serviceConfig.MemoryHigh = "2G";
  systemd.services.mimir.serviceConfig.Restart = "always";
  systemd.services.mimir.serviceConfig.RestartSec = "30s";
  systemd.services.mimir.stopIfChanged = false;
  systemd.services.mimir.restartIfChanged = false;
  systemd.services.mimir.serviceConfig.TimeoutStartSec = "5min";

  services.mimir.extraFlags = [ "-config.expand-env=true" ];
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

    configuration = {
      multitenancy_enabled = false;
      limits = {
        # Unbounded ingestion turned a scrape spike into an OOM. These fit a
        # two-node all-in-one deploy on 4–6 GiB VMs; raise them if the series
        # count is actually that high, after giving the VMs more RAM.
        ingestion_rate = 25000;
        ingestion_burst_size = 100000;
        max_global_series_per_user = 300000;
        out_of_order_time_window = "1h";
        accept_ha_samples = true;
        ha_cluster_label = "cluster";
        ha_replica_label = "__replica__";
        # Tenant limit (not compactor.*). Minimum 4h; lower values disable it.
        # Ghost blocks without meta.json abort the whole compaction job.
        compactor_partial_block_deletion_delay = "4h";
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
          endpoint = "proxmox-lb:3902";
          region = "garage";
          bucket_name = "mimir";
          access_key_id = "\${MIMIR_S3_ACCESS_KEY_ID}";
          secret_access_key = "\${MIMIR_S3_SECRET_ACCESS_KEY}";
          insecure = true;
          bucket_lookup_type = "path";
        };
        tsdb = {
          dir = "/var/lib/mimir/tsdb";
        };
        # Compaction has been failing on Garage keys the index still lists
        # (missing meta.json), so cleanup never rewrites bucket-index.json.gz.
        # The Node Exporter dashboard queries now-24h; 1h then 500s every panel.
        # Grafana's Prometheus plugin surfaces that 500 as "couldn't be parsed".
        bucket_store.bucket_index.max_stale_period = "24h";
      };
      memberlist = {
        node_name = "mimir-v4-${config.networking.hostName}";
        cluster_label = "mimir-cluster";
        bind_addr = [ "\${MIMIR_CLUSTER_IP}" ];
        bind_port = 7947;
        join_members = [
          "\${JOIN_OBSERVABILITY_1}"
          "\${JOIN_OBSERVABILITY_2}"
        ];
        advertise_addr = "\${MIMIR_CLUSTER_IP}";
        advertise_port = 7947;
        dead_node_reclaim_time = "30s";
        rejoin_interval = "30s";
        leave_timeout = "5s";
        gossip_interval = "10s";
        packet_dial_timeout = "5s";
        retransmit_factor = 3;
        gossip_nodes = 3;
      };
      ingester.ring = {
        instance_addr = "\${MIMIR_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
        # Two ingesters. RF=2 needed both acks; one obs node down stopped writes.
        # Garage already RF=2, so ingest RF=1 is the availability choice.
        replication_factor = 1;
      };
      distributor = {
        ring = {
          instance_addr = "\${MIMIR_CLUSTER_IP}";
          instance_interface_names = [ "tailscale0" ];
        };
        ha_tracker = {
          enable_ha_tracker = true;
          kvstore.store = "memberlist";
        };
      };
      ruler = {
        ring = {
          instance_addr = "\${MIMIR_CLUSTER_IP}";
          instance_interface_names = [ "tailscale0" ];
        };
        rule_path = "/tmp/mimir-ruler";
        alertmanager_url = "http://proxmox-observability-1:9093,http://proxmox-observability-2:9093";
      };
      ruler_storage = {
        backend = "local";
        local.directory = "/etc/mimir-rules";
      };
      overrides_exporter.ring = {
        instance_addr = "\${MIMIR_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
      };
      compactor = {
        data_dir = "/var/lib/mimir/compactor";
        compaction_interval = "15m";
        cleanup_interval = "15m";
        sharding_ring = {
          instance_addr = "\${MIMIR_CLUSTER_IP}";
          instance_interface_names = [ "tailscale0" ];
        };
      };
      store_gateway.sharding_ring = {
        instance_addr = "\${MIMIR_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
      };
      alertmanager.sharding_ring.instance_interface_names = [ "tailscale0" ];
    };
  };
}
