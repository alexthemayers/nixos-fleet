{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."postgres/vaultwarden_password" = {
    owner = "postgres";
  };
  sops.secrets."postgres/immich_password" = {
    owner = "postgres";
  };

  services.postgresql = {
    enable = true;

    package = pkgs.postgresql_18;

    # Enable TCP/IP connections (required for network access)
    enableTCPIP = true;

    settings = {
      port = 5432;
      # Memory tuning (Example assumes ~1GB RAM allocated to the host)
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

      max_connections = 100;

      log_destination = "stderr";
      logging_collector = "on";
      log_directory = "log";
      log_filename = "postgresql-%a.log";
      log_rotation_age = "1d";
      log_rotation_size = 0;
      log_min_duration_statement = 1000;
      log_checkpoints = "on";
      log_connections = "on";
      log_disconnections = "on";
      log_lock_waits = "on";

      shared_preload_libraries = [ "vchord" ];
    };

    ensureDatabases = [
      "vaultwarden"
      "immich"
    ];
    ensureUsers = [
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
      {
        name = "immich";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
    extensions = ps: [
      ps.pgvector
      ps.vectorchord
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
# A dedicated oneshot service that guarantees Postgres is fully initialized first
  systemd.services.postgresql-custom-setup = let
    extensions = [
      "unaccent"
      "uuid-ossp"
      "cube"
      "earthdistance"
      "pg_trgm"
      "vector"
      "vchord"
    ];
    sqlFile = pkgs.writeText "immich-pgvectors-setup.sql" (''
      SELECT COALESCE(installed_version, ''') AS vchord_version_before FROM pg_available_extensions WHERE name = 'vchord' \gset
      ${lib.concatMapStringsSep "\n" (ext: "CREATE EXTENSION IF NOT EXISTS \"${ext}\";") extensions}
      ${lib.concatMapStringsSep "\n" (ext: "ALTER EXTENSION \"${ext}\" UPDATE;") extensions}
      ALTER SCHEMA public OWNER TO immich;
      SELECT COALESCE(installed_version, ''') AS vchord_version_after FROM pg_available_extensions WHERE name = 'vchord' \gset

      SELECT (:'vchord_version_before' != ''' AND :'vchord_version_before' != :'vchord_version_after') AS has_vchord_updated \gset
      \if :has_vchord_updated
        REINDEX INDEX face_index;
        REINDEX INDEX clip_index;
      \endif
    '');
  in {
    description = "Custom PostgreSQL Setup for Immich and Vaultwarden";
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };

    script = ''
      PSQL="${config.services.postgresql.package}/bin/psql -tA"

      # Execute Immich extension setup
      $PSQL -d immich -f "${sqlFile}"

      $PSQL -c "ALTER ROLE immich SET search_path TO immich, public, vectors;"

      # Setup passwords
      if [ -f "${config.sops.secrets."postgres/vaultwarden_password".path}" ]; then
        password=$(tr -d '\n' < "${config.sops.secrets."postgres/vaultwarden_password".path}")
        $PSQL -c "ALTER ROLE vaultwarden WITH PASSWORD '$password';"
      fi
      if [ -f "${config.sops.secrets."postgres/immich_password".path}" ]; then
        password=$(tr -d '\n' < "${config.sops.secrets."postgres/immich_password".path}")
        $PSQL -c "ALTER ROLE immich WITH PASSWORD '$password';"
      fi
    '';
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
}
