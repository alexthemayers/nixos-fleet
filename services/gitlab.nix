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
    #    "gitlab/runner_token" = {
    #      owner = "gitlab-runner";
    #      group = "gitlab-runner";
    #      mode = "0440";
    #    };
  };
  users.groups."${config.services.gitlab.group}" = { };
  users.users."${config.services.gitlab.user}" = {
    isSystemUser = true;
    group = "${config.services.gitlab.group}";
  };
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
      enable = false;
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
        -o StrictHostKeyChecking=no" \
        /var/gitlab/state/backup/ \
        alex@rpi4:/mnt/usb-backup/gitlab_backups/
    '';
  };

  #  services.gitlab-runner = {
  #    enable = true;
  #    services = {
  #      shell-runner = {
  #        executor = "shell";
  #        authenticationTokenConfigFile = config.sops.secrets.gitlab_runner_token.path;
  #        limit = 4;
  #        tagList = [
  #          "nixos"
  #          "shell"
  #        ];
  #      };
  #    };
  #  };
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
        '';
      };
    };
  };
}
