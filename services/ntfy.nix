{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.users.alertmanager-ntfy = {
    group = "alertmanager-ntfy";
    isSystemUser = true;
  };
  users.groups.alertmanager-ntfy = { };

  sops.secrets."ntfy/alertmanager_password" = {
    owner = "ntfy-sh";
  };

  sops.secrets."ntfy/password" = {
    owner = "ntfy-sh";
  };

  sops.templates."alertmanager-ntfy.yml" = {
    owner = "alertmanager-ntfy";
    group = "alertmanager-ntfy";
    content = ''
      ntfy:
        baseurl: "http://127.0.0.1:2586"
        notification:
          topic: "alerts"
        auth:
          basic:
            username: "alertmanager"
            password: "${config.sops.placeholder."ntfy/alertmanager_password"}"
    '';
  };

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.alexmayers.co.za";
      listen-http = ":2586";
      behind-proxy = true;
      upstream-url = "https://ntfy.sh";
      auth-default-access = "deny-all";
    };
  };

  systemd.services.ntfy-sh.serviceConfig.DynamicUser = lib.mkForce false;

  systemd.services.ntfy-custom-setup = {
    description = "Custom ntfy setup for Alertmanager access";
    requires = [ "ntfy-sh.service" ];
    after = [ "ntfy-sh.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ntfy-sh";
    };
    script = ''
      # Wait for ntfy-sh to start and initialize the database
      for i in {1..30}; do
        if [ -f "/var/lib/ntfy-sh/user.db" ]; then
          break
        fi
        echo "Waiting for /var/lib/ntfy-sh/user.db to exist..."
        sleep 1
      done

      if [ -f "${config.sops.secrets."ntfy/alertmanager_password".path}" ]; then
        password=$(tr -d '\n' < "${config.sops.secrets."ntfy/alertmanager_password".path}")
        
        # Create user if not exists, otherwise update password
        export NTFY_PASSWORD="$password"
        ${pkgs.ntfy-sh}/bin/ntfy user -H /var/lib/ntfy-sh/user.db add --role=user alertmanager || ${pkgs.ntfy-sh}/bin/ntfy user -H /var/lib/ntfy-sh/user.db change-pass alertmanager
        
        # Grant write access to alerts topic
        ${pkgs.ntfy-sh}/bin/ntfy access -H /var/lib/ntfy-sh/user.db alertmanager alerts write-only
      fi

      if [ -f "${config.sops.secrets."ntfy/password".path}" ]; then
        password=$(tr -d '\n' < "${config.sops.secrets."ntfy/password".path}")
        
        # Create user if not exists, otherwise update password
        export NTFY_PASSWORD="$password"
        ${pkgs.ntfy-sh}/bin/ntfy user -H /var/lib/ntfy-sh/user.db add --role=admin alex || ${pkgs.ntfy-sh}/bin/ntfy user -H /var/lib/ntfy-sh/user.db change-pass alex
      fi
    '';
  };

  systemd.services.alertmanager-ntfy = {
    description = "Alertmanager to ntfy forwarder";
    after = [
      "network.target"
      "ntfy-sh.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.alertmanager-ntfy}/bin/alertmanager-ntfy --configs ${
        config.sops.templates."alertmanager-ntfy.yml".path
      } --http-addr :8095";
      Restart = "always";
      User = "alertmanager-ntfy";
      Group = "alertmanager-ntfy";
    };
  };
}
