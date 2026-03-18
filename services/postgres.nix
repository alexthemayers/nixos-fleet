{ config, pkgs, ... }:
{
  services.postgresql = {
    enable = true;

    package = pkgs.postgresql_18;

    # Enable TCP/IP connections (required for network access)
    enableTCPIP = true;

    settings = {
      port = 5432;
      # Memory tuning (Example assumes ~8GB RAM allocated to the host)
      shared_buffers = "256MB"; # Typically 25% of system RAM
      work_mem = "16MB"; # Per-connection memory for sorts/hashes
      maintenance_work_mem = "512MB";
      effective_cache_size = "768MB"; # Typically 75% of system RAM

      # Write-Ahead Log (WAL) and Checkpointing
      wal_level = "replica"; # Required for replication and advanced backups
      max_wal_size = "2GB";
      min_wal_size = "1GB";
      checkpoint_completion_target = 0.9;
      checkpoint_timeout = "15min";

      # Connections
      max_connections = 100;

      # Observability and Logging
      log_destination = "stderr";
      logging_collector = "on";
      log_directory = "log";
      log_filename = "postgresql-%a.log";
      log_rotation_age = "1d";
      log_rotation_size = 0;
      log_min_duration_statement = 1000; # Log queries taking > 1s
      log_checkpoints = "on";
      log_connections = "on";
      log_disconnections = "on";
      log_lock_waits = "on";

      shared_preload_libraries = [
        # "vectors.so" # only pertains to pgvecto-rs
        # "vchord.so"
      ];
    };
    ensureDatabases = [
      "gitea"
    ];
    ensureUsers = [
      {
        name = "gitea";
      }
    ];
    authentication = pkgs.lib.mkOverride 10 ''
      # type  database        DBuser          origin-address          auth-method
      # Local socket access (required for local administration and backups)
      local   all             all                                     peer

      # Localhost access
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256

      # Allow connections strictly from the Tailscale network
      host    all             all             100.64.0.0/10           scram-sha-256
      host    all             all             fd7a:115c:a1e0::/48     scram-sha-256
    '';

  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
}
