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
    "postgres/vikunja_password" = {
      owner = "postgres";
    };
    "postgres/coder_password" = {
      owner = "postgres";
    };
    "postgres/paperless_password" = {
      owner = "postgres";
    };
    "postgres/attic_password" = {
      owner = "postgres";
    };
    "ssh_backup/privkey" = {
      owner = "postgres";
    };
  };

  services.prometheus.exporters.postgres = {
    enable = true;
    runAsLocalSuperUser = true;
    dataSourceName = "user=postgres host=/run/postgresql port=5433 sslmode=disable";
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

        stats_users = "pgbouncer_exporter";

        # Global pooling settings. Sized for the 1 GiB hub: each Postgres
        # backend is ~8–15 MiB private plus shared_buffers. See
        # docs/adr/2026-09-04-xcloud-postgres-1g.md.
        pool_mode = "transaction";
        max_client_conn = 200;
        default_pool_size = 4;
        min_pool_size = 0;
        # auth_query and bursty session pools were leaving backends around
        # for days (default 600s is not enough when clients keep touching
        # them). 60s drops truly idle servers; live clients reopen.
        server_idle_timeout = 60;
        server_lifetime = 3600;
        # Grafana can sit idle-in-transaction; Immich holds advisory locks
        # in an open transaction for the life of a job. 120s killed those
        # sessions (CONNECTION_CLOSED every ~2m) and crash-looped
        # immich-server. Grafana's pin is already capped by pool_size=5.
        # 0 disables the timer. Session-mode clients must not be cut here.
        idle_transaction_timeout = 0;

        # extra_float_digits: libpq/JDBC. search_path: pgx (Vikunja 2.5+).
        ignore_startup_parameters = "extra_float_digits,search_path";
      };

      databases = {
        # pool_size defaults to default_pool_size=4. Immich API +
        # microservices open more than 4 session connections; without an
        # explicit pool_size they queue and then query_wait_timeout.
        "immich" = "host=127.0.0.1 port=5433 pool_mode=session pool_size=8 max_db_connections=8";
        "coder" = "host=127.0.0.1 port=5433 pool_mode=session pool_size=5 max_db_connections=5";
        "vikunja" = "host=127.0.0.1 port=5433 pool_mode=session pool_size=3 max_db_connections=3";
        "gitlab" = "host=127.0.0.1 port=5433 pool_size=8";
        "keycloak" = "host=127.0.0.1 port=5433 pool_size=3";
        # Keep 5: Grafana idle-in-transaction pins a server in transaction
        # mode. Two obs nodes with max_open_conn=5 already sit at this cap.
        "grafana" = "host=127.0.0.1 port=5433 pool_size=5";
        "vaultwarden" = "host=127.0.0.1 port=5433 pool_size=2";
        "paperless" = "host=127.0.0.1 port=5433 pool_size=3";
        # sqlx/sea-orm prepared statements need a session. One atticd
        # (proxmox-dev) opens a sqlx pool (~10). Cap of 5 made uploads
        # wait 120s then fail with query_wait_timeout. Fill spikes may
        # use zram; do not cut this to save idle RAM.
        "attic" = "host=127.0.0.1 port=5433 pool_mode=session pool_size=20 max_db_connections=20";
        # auth_query + the postgres exporter. default_pool_size=20 used
        # to leave five idle backends on this database alone.
        "postgres" = "host=127.0.0.1 port=5433 pool_size=2";

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

      # 1 GiB hub budget: shared_buffers is ~13% of RAM so Alloy, Redis,
      # exporters, and page cache still fit. work_mem is per-sort, so keep
      # it small and let PgBouncer bound concurrency.
      shared_buffers = "128MB";
      work_mem = "4MB";
      maintenance_work_mem = "64MB";
      effective_cache_size = "256MB";
      temp_buffers = "4MB";
      huge_pages = "off";
      jit = "off";

      max_worker_processes = 2;
      max_parallel_workers = 1;
      max_parallel_workers_per_gather = 0;
      max_parallel_maintenance_workers = 1;
      autovacuum_max_workers = 1;

      random_page_cost = "1.1";
      effective_io_concurrency = 200;

      # Write-Ahead Log (WAL) & Checkpoints. WAL lives on the 10GB data
      # disk (Immich is already ~950MB); 2GB max_wal_size was a third of
      # that volume and did not need to sit in RAM.
      wal_level = "replica";
      max_wal_size = "512MB";
      min_wal_size = "64MB";
      checkpoint_completion_target = 0.9;
      checkpoint_timeout = "15min";

      # Must stay above the sum of PgBouncer pool caps (59) plus
      # autovacuum and superuser_reserved_connections.
      max_connections = 70;

      # Logging
      log_destination = lib.mkForce "jsonlog";
      logging_collector = "on";
      log_directory = "log";
      log_filename = "postgresql-%H.log";
      log_rotation_age = "1h";
      log_truncate_on_rotation = "on";
      log_file_mode = "0640";
      log_rotation_size = 0;

      log_min_duration_statement = 1000;
      log_checkpoints = "on";
      log_connections = "off";
      log_disconnections = "off";
      log_lock_waits = "on";

      shared_preload_libraries = [ "vchord" ];
    };

    ensureDatabases = [
      "gitlab"
      "vaultwarden"
      "immich"
      "grafana"
      "keycloak"
      "vikunja"
      "coder"
      "paperless"
      "attic"
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
        name = "vikunja";
        ensureDBOwnership = true;
      }
      {
        name = "coder";
        ensureDBOwnership = true;
      }
      {
        name = "paperless";
        ensureDBOwnership = true;
      }
      {
        name = "attic";
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

      # Allow PgBouncer auth_query to look up passwords via TCP.
      host    postgres        postgres        127.0.0.1/32            trust
      host    postgres        postgres        ::1/128                 trust

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
        set -euo pipefail

        PSQL="${config.services.postgresql.package}/bin/psql -v ON_ERROR_STOP=1 -p 5433 -tA"

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

        # vector and vchord are created without a SCHEMA clause above, so they
        # live in public. The old "vectors" entry was the pgvecto.rs schema,
        # which this server does not have.
        $PSQL -c "ALTER ROLE immich SET search_path TO immich, public;"

        # A missing secret file is a deployment error, not something to skip:
        # silently leaving a role's password unset breaks that service later
        # while this unit still reports success.
        set_role_password() {
          role="$1"
          file="$2"
          if [ ! -r "$file" ]; then
            echo "Secret file for role $role is missing or unreadable: $file" >&2
            return 1
          fi
          password=$(tr -d '\n' < "$file")
          echo "ALTER ROLE $role WITH PASSWORD :'pw';" | $PSQL -v "pw=$password"
        }

        set_role_password vaultwarden       "${config.sops.secrets."postgres/vaultwarden_password".path}"
        set_role_password immich            "${config.sops.secrets."postgres/immich_password".path}"
        set_role_password grafana           "${config.sops.secrets."postgres/grafana_password".path}"
        set_role_password keycloak          "${config.sops.secrets."postgres/keycloak_password".path}"
        set_role_password gitlab            "${config.sops.secrets."postgres/gitlab_password".path}"
        set_role_password vikunja           "${config.sops.secrets."postgres/vikunja_password".path}"
        set_role_password coder             "${config.sops.secrets."postgres/coder_password".path}"
        set_role_password paperless         "${config.sops.secrets."postgres/paperless_password".path}"
        set_role_password attic             "${config.sops.secrets."postgres/attic_password".path}"
        set_role_password pgbouncer_exporter "${
          config.sops.secrets."postgres/pgbouncer_exporter/db_password".path
        }"
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
    environment.PGPORT = "5433";
    # postStart runs as postgres, which cannot write to /run itself. Let systemd
    # own the scratch directory so the verification redirect below can create it.
    serviceConfig.RuntimeDirectory = "postgresql-backup";
    postStart = ''
      set -euo pipefail

      TIMESTAMP=$(${pkgs.coreutils}/bin/date +"%Y-%m-%d_%H-%M-%S")
      if [ -f /var/backup/postgresql/all.sql.zstd ]; then
        mv /var/backup/postgresql/all.sql.zstd /var/backup/postgresql/all_$TIMESTAMP.sql.zstd
      fi

      # Copy first, verify with a second checksum pass, and only then delete the
      # local artifact. --remove-source-files deletes on transfer, so a full
      # destination or a dropped connection used to lose the only local copy.
      SSH_CMD="${pkgs.openssh}/bin/ssh -i ${
        config.sops.secrets."ssh_backup/privkey".path
      } -o StrictHostKeyChecking=yes"

      ${pkgs.rsync}/bin/rsync -av -e "$SSH_CMD" \
        /var/backup/postgresql/ \
        alex@rpi4:/mnt/usb-backup/postgres_backups/

      ${pkgs.rsync}/bin/rsync -a --checksum --dry-run --itemize-changes -e "$SSH_CMD" \
        /var/backup/postgresql/ \
        alex@rpi4:/mnt/usb-backup/postgres_backups/ > "$RUNTIME_DIRECTORY/verify.txt"

      if [ -s "$RUNTIME_DIRECTORY/verify.txt" ]; then
        echo "Backup verification failed; these paths still differ on rpi4:" >&2
        cat "$RUNTIME_DIRECTORY/verify.txt" >&2
        exit 1
      fi

      ${pkgs.findutils}/bin/find /var/backup/postgresql -maxdepth 1 -type f -name '*.sql.zstd' -delete
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

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    5432 # PgBouncer (clients). Raw Postgres on 5433 stays closed on purpose.
    9187 # postgres exporter
    9127 # pgbouncer exporter
  ];
}
