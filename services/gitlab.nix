{
  config,
  pkgs,
  lib,
  ...
}:
{
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
      port = 5005;
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
        signup_enabled = true;
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
        block_auto_created_users = false;
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
              client_auth_method = "query";
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

  systemd.services.gitlab-backup = {
    onSuccess = [ "gitlab-backup-sync.service" ];
    # Shadow the v16 pg_dump with the v17 pg_dump dynamically at runtime!
    serviceConfig = {
      BindReadOnlyPaths = [
        "${pkgs.postgresql_17}/bin:${pkgs.postgresql_16}/bin"
      ];
    };
  };
  systemd.services.gitlab-backup-sync = {
    description = "Push GitLab backups";
    serviceConfig = {
      Type = "oneshot";
      User = "gitlab";
    };
    script = ''
      mkdir -p /var/gitlab/state/backup
      ${pkgs.rsync}/bin/rsync -avz --remove-source-files \
        -e "${pkgs.openssh}/bin/ssh \
        -i ${config.sops.secrets."ssh_backup/privkey".path} \
        -o StrictHostKeyChecking=accept-new" \
        /var/gitlab/state/backup/ \
        alex@rpi4:/mnt/usb-backup/gitlab_backups/
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
      "x-systemd.idle-timeout=600"
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
}
