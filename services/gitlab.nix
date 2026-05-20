{ config, lib, ... }:
{
  sops.secrets = {
    "postgres/gitlab_password" = {
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
    };
    #    backup = {
    #      startAt = "02:00";
    #      keepTime = 604800;
    #    };
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

    virtualHosts.${config.services.gitlab.host} = {
      # When using tunnel, Cloudflare handles HTTPS
      # Nginx serves HTTP locally, tunnel connects to it. Goddamn magic
      enableACME = false;
      forceSSL = false;

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
          client_max_body_size 250m;
        '';
      };
    };
  };
}
