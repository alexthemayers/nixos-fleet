{
  config,
  pkgs,
  lib,
  ...
}:
{
  fleet.waitFor.postgres.gitlab.forServices = [
    "gitlab.service"
    "gitlab-db-config.service"
  ];

  sops.secrets = {
    "postgres/gitlab_password" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/client_secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/root_password" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/db_encryption_secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/jws" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/otp" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/active_record/primary" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/active_record/deterministic" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "gitlab/active_record/salt" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0440";
    };
    "ssh_backup/privkey" = {
      owner = "gitlab";
      group = "gitlab";
    };
    "gitlab/registry_key" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/registry_cert" = {
      mode = "0444";
    };
  };
  users.groups."${config.services.gitlab.group}" = { };
  users.users."${config.services.gitlab.user}" = {
    isSystemUser = true;
    group = "${config.services.gitlab.group}";
  };
  services.dockerRegistry.listenAddress = "0.0.0.0";
  services.gitlab = {
    enable = true;
    user = "gitlab";
    group = "gitlab";

    host = "gitlab.alexmayers.co.za";
    port = 443;
    https = true;

    databaseCreateLocally = false;
    databaseUsername = "gitlab";
    databaseHost = "xcloud-postgres";
    databaseName = "gitlab";
    databasePasswordFile = config.sops.secrets."postgres/gitlab_password".path;
    initialRootPasswordFile = config.sops.secrets."gitlab/root_password".path;
    secrets = {
      secretFile = config.sops.secrets."gitlab/secret".path;
      dbFile = config.sops.secrets."gitlab/db_encryption_secret".path;
      otpFile = config.sops.secrets."gitlab/otp".path;
      jwsFile = config.sops.secrets."gitlab/jws".path;
      activeRecordPrimaryKeyFile = config.sops.secrets."gitlab/active_record/primary".path;
      activeRecordDeterministicKeyFile = config.sops.secrets."gitlab/active_record/deterministic".path;
      activeRecordSaltFile = config.sops.secrets."gitlab/active_record/salt".path;
    };
    registry = {
      enable = true;
      settings = {
        http.addr = "0.0.0.0:5005";
        # nixpkgs defaults this to "prefer", which tries a local unix socket
        # (postgresql.target) that does not exist on this host. Storage is the
        # filesystem bind at /var/lib/docker-registry.
        database.enabled = false;
      };
      externalAddress = "registry.alexmayers.co.za";
      externalPort = 443;
      certFile = config.sops.secrets."gitlab/registry_cert".path;
      keyFile = config.sops.secrets."gitlab/registry_key".path;
    };
    pages = {
      enable = false;
    };
    smtp = {
      enable = false;
    };

    extraConfig = {
      gitlab = {
        email_from = "a.mayers102@gmail.com";
        email_display_name = "Alex Mayers GitLab";
        email_reply_to = "a.mayers102@gmail.com";
        signup_enabled = false;
        require_admin_approval_after_user_signup = true;
      };
      monitoring = {
        ip_whitelist = [
          "127.0.0.0/8"
          "100.64.0.0/10"
        ];
      };
      gravatar.enabled = true;
      omniauth = {
        enabled = true;
        allow_single_sign_on = [ "openid_connect" ];
        # Accounts created from an OIDC login stay blocked until an admin
        # approves them, matching require_admin_approval_after_user_signup.
        block_auto_created_users = true;
        auto_link_user = [ "openid_connect" ];
        auto_sign_in_with_provider = "openid_connect";
        providers = [
          {
            name = "openid_connect";
            label = "Keycloak";
            args = {
              name = "openid_connect";
              scope = [
                "openid"
                "profile"
                "email"
              ];
              response_type = "code";
              issuer = "https://identity.alexmayers.co.za/realms/master";
              # "query" puts the client secret in the request URL, where it
              # lands in access logs and Referer headers. Prefer "basic"
              client_auth_method = "basic";
              discovery = true;
              uid_field = "preferred_username";
              client_options = {
                identifier = "gitlab";
                secret = "<%= File.read('${config.sops.secrets."gitlab/client_secret".path}').strip %>";
                redirect_uri = "https://gitlab.alexmayers.co.za/users/auth/openid_connect/callback";
              };
            };
          }
        ];
      };
    };
    backup = {
      startAt = "*-*-* 03:00:00";
    };
    puma = {
      workers = 2;
      threadsMin = 1;
      threadsMax = 4;
    };
    sidekiq = {
      concurrency = 10;
    };
    extraEnv = {
      RUBY_GC_MALLOC_LIMIT = "67108864";
      RUBY_GC_MALLOC_LIMIT_MAX = "134217728";
      RUBY_GC_OLDMALLOC_LIMIT = "67108864";
      RUBY_GC_OLDMALLOC_LIMIT_MAX = "134217728";
      RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR = "1.05";
    };
  };

  systemd.services.gitlab-container-registry = {
    requires = lib.mkForce [ ];
    after = lib.mkForce [
      "network.target"
      "gitlab-registry-cert.service"
    ];
  };

  # gitlab-config rsyncs packaged feature-flag YAML into state and never
  # deletes a flag that moved from wip/ to beta/. Feature::Definition then
  # aborts gitlab-db-config (seen with granular_personal_access_tokens and
  # rapid_diffs_on_mr_show on 19.0.4). Drop the wip copy when beta exists.
  systemd.services.gitlab-config.serviceConfig.ExecStartPost =
    pkgs.writeShellScript "gitlab-dedup-feature-flags" ''
      set -euo pipefail
      flags=${config.services.gitlab.statePath}/config/feature_flags
      if [ -d "$flags/beta" ] && [ -d "$flags/wip" ]; then
        for f in "$flags/beta"/*.yml; do
          [ -e "$f" ] || continue
          rm -f "$flags/wip/$(basename "$f")"
        done
      fi
    '';
  systemd.services.gitlab-db-config.preStart = lib.mkAfter ''
    flags=${config.services.gitlab.statePath}/config/feature_flags
    if [ -d "$flags/beta" ] && [ -d "$flags/wip" ]; then
      for f in "$flags/beta"/*.yml; do
        [ -e "$f" ] || continue
        rm -f "$flags/wip/$(basename "$f")"
      done
    fi
  '';

  systemd.services.gitlab-backup = {
    onSuccess = [ "gitlab-backup-sync.service" ];
    # gitlab-backup shells out to whichever pg_dump the GitLab module put on its
    # PATH, and that client must not be older than the 17 server on
    # xcloud-postgres. Prepending the matching client is version-agnostic; the
    # previous BindReadOnlyPaths shadowed one hardcoded store path over another
    # and would have failed to start the moment nixpkgs moved GitLab off
    # postgresql_16.
    path = lib.mkBefore [ pkgs.postgresql_17 ];
  };
  systemd.services.gitlab-backup-sync = {
    description = "Push GitLab backups";
    serviceConfig = {
      Type = "oneshot";
      User = "gitlab";
    };
    script = ''
      set -euo pipefail

      mkdir -p /var/gitlab/state/backup

      SSH_CMD="${pkgs.openssh}/bin/ssh -i ${
        config.sops.secrets."ssh_backup/privkey".path
      } -o StrictHostKeyChecking=yes"

      # Copy, verify, then delete. --remove-source-files deleted the local
      # archive as a side effect of transfer, so a half-transfer left neither
      # side with a complete backup.
      ${pkgs.rsync}/bin/rsync -avz -e "$SSH_CMD" \
        /var/gitlab/state/backup/ \
        alex@rpi4:/mnt/usb-backup/gitlab_backups/

      ${pkgs.rsync}/bin/rsync -a --checksum --dry-run --itemize-changes -e "$SSH_CMD" \
        /var/gitlab/state/backup/ \
        alex@rpi4:/mnt/usb-backup/gitlab_backups/ > /tmp/gitlab-backup-verify.txt

      if [ -s /tmp/gitlab-backup-verify.txt ]; then
        echo "Backup verification failed; these paths still differ on rpi4:" >&2
        cat /tmp/gitlab-backup-verify.txt >&2
        exit 1
      fi

      find /var/gitlab/state/backup -maxdepth 1 -type f -delete
    '';
  };

  users.users.nginx.extraGroups = [ "${config.services.gitlab.group}" ];
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    commonHttpConfig = ''
      log_format json_analytics escape=json '{'
        '"time":"$time_iso8601",'
        '"remote_addr":"$remote_addr",'
        '"request_uri":"$request_uri",'
        '"request_method":"$request_method",'
        '"status":"$status",'
        '"body_bytes_sent":"$body_bytes_sent",'
        '"request_time":"$request_time",'
        '"http_referrer":"$http_referer",'
        '"http_user_agent":"$http_user_agent"'
      '}';

      proxy_cache_path /var/cache/nginx/gitlab levels=1:2 keys_zone=gitlab:10m max_size=1g inactive=60m use_temp_path=off;
    '';

    virtualHosts.${config.services.gitlab.host} = {
      # When using tunnel, Cloudflare handles HTTPS
      # Nginx serves HTTP locally, tunnel connects to it. Goddamn magic
      enableACME = false;
      forceSSL = false;

      extraConfig = ''
        access_log syslog:server=unix:/dev/log,facility=user,severity=info json_analytics;
      '';

      listen = [
        {
          addr = "0.0.0.0";
          port = 8080;
        }
      ];

      locations."/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Ssl on;

          # Allow pushing large repositories/commits up to 250MB over HTTP
          client_max_body_size 1G;

          proxy_cache gitlab;
          proxy_cache_revalidate on;
          proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
          proxy_cache_background_update on;
          proxy_cache_lock on;

          # Never serve or store a cached response for an authenticated request.
          # Without this, correctness depends entirely on GitLab tagging every
          # authenticated route with Cache-Control: private.
          proxy_cache_bypass $http_authorization $cookie__gitlab_session $http_cookie;
          proxy_no_cache     $http_authorization $cookie__gitlab_session $http_cookie;
        '';
      };
    };
  };

  # Bind mount GitLab registry storage to the build cache target path
  fileSystems."/var/lib/gitlab/shared/registry" = lib.mkIf config.services.gitlab.registry.enable {
    device = "/mnt/ssd/container-registry/gitlab";
    fsType = "none";
    options = [
      "bind"
      "nofail"
      "x-systemd.requires=container-registry-dir-init.service"
      "x-systemd.after=container-registry-dir-init.service"
    ];
  };

  fleet.waitForHost.gitlab.host = "truenas-scale";

  fileSystems."/mnt/nfs-gitlab" = {
    device = "truenas-scale:/mnt/ssd/gitlab";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      # Do not idle-unmount. /var/gitlab/state is a loop device backed by this
      # share; an idle unmount leaves kworker in D-state and hangs reboot on
      # "A stop job is running for /var/gitlab/state".
      "x-systemd.requires=wait-for-host-gitlab.service"
      "x-systemd.after=wait-for-host-gitlab.service"
      "_netdev"
    ];
  };

  fileSystems."/var/gitlab/state" = {
    device = "/mnt/nfs-gitlab/gitlab-state.img";
    fsType = "ext4";
    options = [
      "loop"
      "x-systemd.requires=mnt-nfs\\x2dgitlab.mount"
      "_netdev"
    ];
  };

  # Overlay a tmpfs onto the GitLab sockets directory to prevent NFS IPC failures
  fileSystems."/var/gitlab/state/tmp/sockets" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "size=10M"
      "mode=1777"
      "x-systemd.requires=var-gitlab-state.mount"
      "x-systemd.after=var-gitlab-state.mount"
      "_netdev"
    ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8080 # GitLab nginx (caddy-internal + Prometheus gitlab job)
    5005 # GitLab container registry (caddy-internal registry.alexmayers.co.za)
  ];
}
