{
  config,
  pkgs,
  lib,
  ...
}:
{

  sops.secrets = {
    "postgres/pgbouncer_exporter/db_password" = {
      owner = "postgres";
    };
    "postgres/pgbouncer_exporter/env_file" = {
      owner = "postgres";
    };
    "postgres/gitlab_password" = {
      owner = "postgres";
    };
    "postgres/vaultwarden_password" = {
      owner = "postgres";
    };
    "postgres/immich_password" = {
      owner = "postgres";
    };
    "postgres/grafana_password" = {
      owner = "postgres";
    };
    "postgres/keycloak_password" = {
      owner = "postgres";
    };
    "ssh_backup/privkey" = {
      owner = "postgres";
    };
  };

  services.prometheus.exporters.postgres = {
    enable = true;
    runAsLocalSuperUser = true;
  };
  services.prometheus.exporters.pgbouncer = {
    enable = true;
    connectionEnvFile = config.sops.secrets."postgres/pgbouncer_exporter/env_file".path;
  };

  services.pgbouncer = {
    enable = true;

    settings = {
      pgbouncer = {
        listen_port = 5432;
        listen_addr = "*";

        # Dynamically query Postgres for passwords instead of using a static file
        auth_type = "scram-sha-256";
        auth_user = "postgres";
        auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1";
        auth_dbname = "postgres";

        # Allow the exporter to query internal PgBouncer metrics
        stats_users = "pgbouncer_exporter";

        # Global pooling settings
        pool_mode = "transaction";
        max_client_conn = 500;
        default_pool_size = 20;

        ignore_startup_parameters = "extra_float_digits";
      };

      databases = {
        # 1. Force Session mode for the monoliths.
        # We also cap their max backend connections so they don't starve Keycloak/Grafana.
        "immich" = "host=127.0.0.1 port=5433 pool_mode=session max_db_connections=15";
        "gitlab" = "host=127.0.0.1 port=5433 pool_mode=session max_db_connections=15";

        # 2. The Catch-all for everyone else (Keycloak, Grafana, Vaultwarden).
        # They will fall back to the global 'transaction' mode defined in settings below.
        "*" = "host=127.0.0.1 port=5433";
      };
    };
  };

  services.postgresql = {
    enable = true;

    package = pkgs.postgresql_17;

    # Enable TCP/IP connections (required for network access)
    enableTCPIP = true;

    settings = {
      port = 5433;

      # Memory Tuning (Dedicated 2GB RAM)
      shared_buffers = "512MB"; # Exactly 25% of RAM
      work_mem = "4MB"; # Safe threshold: 200 connections * 16MB = 1.6GB max potential allocation
      maintenance_work_mem = "512MB"; # Enough for vector index building without starvation
      effective_cache_size = "1536MB"; # 75% of RAM; tells the planner how much OS cache exists

      # CPU / Parallelism (Dedicated 2 Cores)
      max_worker_processes = 1; # Match total physical cores
      max_parallel_workers_per_gather = 1; # Limits parallel queries to 1 background worker so they don't lock up both cores
      max_parallel_maintenance_workers = 1;

      # Storage Optimizations (Assumes SSD/NVMe)
      random_page_cost = "1.1";
      effective_io_concurrency = 200;

      # Write-Ahead Log (WAL) & Checkpoints
      wal_level = "replica";
      max_wal_size = "4GB";
      min_wal_size = "512MB";
      checkpoint_completion_target = 0.9;
      checkpoint_timeout = "15min";

      max_connections = 50;

      # Logging
      log_destination = lib.mkForce "jsonlog";
      logging_collector = "on";
      log_directory = "log";
      log_filename = "postgresql-%H.log";
      log_rotation_age = "1h";
      log_truncate_on_rotation = "on";
      log_file_mode = "0640";
      log_rotation_size = 0;

      log_min_duration_statement = 0;
      log_checkpoints = "on";
      log_connections = "on";
      log_disconnections = "on";
      log_lock_waits = "on";

      shared_preload_libraries = [ "vchord" ];
    };

    ensureDatabases = [
      "gitlab"
      "vaultwarden"
      "immich"
      "grafana"
      "keycloak"
    ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
      }
      {
        name = "keycloak";
        ensureDBOwnership = true;
      }
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
      {
        name = "immich";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
      {
        name = "pgbouncer_exporter";
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

      # Allow PgBouncer to query passwords seamlessly
      host    all             postgres        127.0.0.1/32            trust
      host    all             postgres        ::1/128                 trust

      # Localhost access
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256

      # Allow connections strictly from the Tailscale network
      host    all             all             100.64.0.0/10           scram-sha-256
      host    all             all             fd7a:115c:a1e0::/48     scram-sha-256
    '';
  };
  # A dedicated oneshot service that guarantees Postgres is fully initialized first
  systemd.services.postgresql-custom-setup =
    let
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
    in
    {
      description = "Custom PostgreSQL Setup for Immich";
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        RemainAfterExit = true;
      };

      script = ''
        PSQL="${config.services.postgresql.package}/bin/psql -p 5433 -tA"

        echo "Waiting for NixOS to finish creating the immich database..."
        retries=30
        until $PSQL -d immich -c '\q' 2>/dev/null; do
          if [ $retries -le 0 ]; then
            echo "Timeout waiting for immich database."
            exit 1
          fi
          sleep 1
          retries=$((retries - 1))
        done

        echo "Database 'immich' is ready. Applying custom setup..."

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
        if [ -f "${config.sops.secrets."postgres/grafana_password".path}" ]; then
          password=$(tr -d '\n' < "${config.sops.secrets."postgres/grafana_password".path}")
          $PSQL -c "ALTER ROLE grafana WITH PASSWORD '$password';"
        fi
        if [ -f "${config.sops.secrets."postgres/keycloak_password".path}" ]; then
          password=$(tr -d '\n' < "${config.sops.secrets."postgres/keycloak_password".path}")
          $PSQL -c "ALTER ROLE keycloak WITH PASSWORD '$password';"
        fi
        if [ -f "${config.sops.secrets."postgres/gitlab_password".path}" ]; then
          password=$(tr -d '\n' < "${config.sops.secrets."postgres/gitlab_password".path}")
          $PSQL -c "ALTER ROLE gitlab WITH PASSWORD '$password';"
        fi
        if [ -f "${config.sops.secrets."postgres/pgbouncer_exporter/db_password".path}" ]; then
          password=$(tr -d '\n' < "${config.sops.secrets."postgres/pgbouncer_exporter/db_password".path}")
          $PSQL -c "ALTER ROLE pgbouncer_exporter WITH PASSWORD '$password';"
        fi
      '';
    };
  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    compression = "zstd";
    location = "/var/backup/postgresql";
    startAt = "*-*-* 02:00:00";
  };
  systemd.services.postgresqlBackup = {
    postStart = ''
      TIMESTAMP=$(${pkgs.coreutils}/bin/date +"%Y-%m-%d_%H-%M-%S")
      if [ -f /var/backup/postgresql/all.sql.zstd ]; then
        mv /var/backup/postgresql/all.sql.zstd /var/backup/postgresql/all_$TIMESTAMP.sql.zstd
      fi
      ${pkgs.rsync}/bin/rsync -avz --remove-source-files \
        -e "${pkgs.openssh}/bin/ssh \
        -i ${config.sops.secrets."ssh_backup/privkey".path} \
        -o StrictHostKeyChecking=no" \
        /var/backup/postgresql/ \
        alex@rpi4:/mnt/usb-backup/postgres_backups/
    '';
  };

  users.users.alloy = {
    isSystemUser = true;
    group = "alloy";
    extraGroups = [ "postgres" ];
  };
  users.groups.alloy = { };
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "postgres" ];

  systemd.tmpfiles.rules = [
    "d /var/lib/postgresql/17 0750 postgres postgres - -"
    "d /var/lib/postgresql/17/log 0750 postgres postgres - -"
  ];

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
}
