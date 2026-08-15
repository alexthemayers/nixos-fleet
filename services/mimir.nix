{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./mimir-rules.nix ];
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
  systemd.services.mimir.serviceConfig.MemoryMax = "2G";
  systemd.services.mimir.serviceConfig.Restart = "always";
  systemd.services.mimir.serviceConfig.RestartSec = "5s";
  systemd.services.mimir.serviceConfig.ExecStart = lib.mkForce (
    let
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "mimir.yaml" config.services.mimir.configuration;
    in
    "/bin/sh -c '"
    + "TAILSCALE_IP=\"\"; "
    + "while [ -z \"$TAILSCALE_IP\" ]; do "
    + "  TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null | head -n1); "
    + "  if [ -z \"$TAILSCALE_IP\" ]; then TAILSCALE_IP=$(${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 2>/dev/null | ${pkgs.gawk}/bin/awk \"/inet / {print \\$2}\" | cut -d/ -f1 | head -n1); fi; "
    + "  if [ -z \"$TAILSCALE_IP\" ]; then sleep 1; fi; "
    + "done; "
    + "export MIMIR_CLUSTER_IP=$TAILSCALE_IP; "
    + "JOIN_OBS_1=$(${pkgs.tailscale}/bin/tailscale ip -4 proxmox-observability-1 2>/dev/null | head -n1); "
    + "if [ -z \"$JOIN_OBS_1\" ]; then JOIN_OBS_1=$(${pkgs.glibc.bin}/bin/getent ahostsv4 proxmox-observability-1.bee-phrygian.ts.net 2>/dev/null | ${pkgs.gawk}/bin/awk \"{print \\$1}\" | head -n1); fi; "
    + "export JOIN_OBSERVABILITY_1=\"\${JOIN_OBS_1:-proxmox-observability-1}:7947\"; "
    + "JOIN_OBS_2=$(${pkgs.tailscale}/bin/tailscale ip -4 proxmox-observability-2 2>/dev/null | head -n1); "
    + "if [ -z \"$JOIN_OBS_2\" ]; then JOIN_OBS_2=$(${pkgs.glibc.bin}/bin/getent ahostsv4 proxmox-observability-2.bee-phrygian.ts.net 2>/dev/null | ${pkgs.gawk}/bin/awk \"{print \\$1}\" | head -n1); fi; "
    + "export JOIN_OBSERVABILITY_2=\"\${JOIN_OBS_2:-proxmox-observability-2}:7947\"; "
    + "JOIN_RPI=$(${pkgs.tailscale}/bin/tailscale ip -4 rpi4 2>/dev/null | head -n1); "
    + "if [ -z \"$JOIN_RPI\" ]; then JOIN_RPI=$(${pkgs.glibc.bin}/bin/getent ahostsv4 rpi4.bee-phrygian.ts.net 2>/dev/null | ${pkgs.gawk}/bin/awk \"{print \\$1}\" | head -n1); fi; "
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

    configuration = {
      multitenancy_enabled = false;
      target = "all";
      limits = {
        ingestion_burst_size = 2147483647;
        max_global_series_per_user = 100000000;
        out_of_order_time_window = "1h";
        accept_ha_samples = true;
        ha_cluster_label = "cluster";
        ha_replica_label = "__replica__";
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
        };
        tsdb = {
          dir = "/var/lib/mimir/tsdb";
        };
      };
      memberlist = {
        node_name = "mimir-v4-${config.networking.hostName}";
        cluster_label = "mimir-cluster";
        bind_addr = [ "\${MIMIR_CLUSTER_IP}" ];
        bind_port = 7947;
        join_members = [
          "\${JOIN_OBSERVABILITY_1}"
          "\${JOIN_OBSERVABILITY_2}"
          "\${JOIN_RPI4}"
        ];
        advertise_addr = "\${MIMIR_CLUSTER_IP}";
        advertise_port = 7947;
        # Faster failure detection and node eviction
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
      compactor.sharding_ring = {
        instance_addr = "\${MIMIR_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
      };
      store_gateway.sharding_ring = {
        instance_addr = "\${MIMIR_CLUSTER_IP}";
        instance_interface_names = [ "tailscale0" ];
      };
      alertmanager.sharding_ring.instance_interface_names = [ "tailscale0" ];
    };
  };
}
