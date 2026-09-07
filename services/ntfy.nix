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

  # One ntfy post per Alertmanager group. alertmanager-ntfy templates the
  # per-alert struct and fans out one push per series.
  sops.templates."alertmanager-ntfy.env" = {
    owner = "alertmanager-ntfy";
    group = "alertmanager-ntfy";
    restartUnits = [ "alertmanager-ntfy.service" ];
    content = ''
      NTFY_PASSWORD=${config.sops.placeholder."ntfy/alertmanager_password"}
      NTFY_BASE=http://proxmox-observability.bee-phrygian.ts.net:2586
    '';
  };

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.alexmayers.co.za";
      listen-http = ":2586";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";
      auth-default-access = "deny-all";
      log-level = "debug";
      enable-metrics = true;
    };
  };

  systemd.services.ntfy-sh.serviceConfig.DynamicUser = lib.mkForce false;

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    2586 # ntfy (edge Caddy reverse_proxy + Prometheus)
  ];

  systemd.services.ntfy-custom-setup = {
    description = "Custom ntfy setup for Alertmanager access";
    requires = [ "ntfy-sh.service" ];
    after = [ "ntfy-sh.service" ];
    wantedBy = [ "multi-user.target" ];
    # Rollback after a newer ntfy has migrated user.db (schema 9) must not
    # re-run the older binary, which then fails the whole switch.
    stopIfChanged = false;
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ntfy-sh";
    };
    script = ''
      set -euo pipefail

      DB=/var/lib/ntfy-sh/user.db
      NTFY="${pkgs.ntfy-sh}/bin/ntfy"

      # Wait for ntfy-sh to start and initialize the database
      ready=0
      for _ in {1..30}; do
        if [ -f "$DB" ]; then
          ready=1
          break
        fi
        echo "Waiting for $DB to exist..."
        sleep 1
      done

      if [ "$ready" -ne 1 ]; then
        echo "ntfy never created $DB; refusing to report success." >&2
        exit 1
      fi

      # "add || change-pass" hid real failures. Treat "already exists" as the
      # only case that should fall through to change-pass; anything else is fatal.
      ensure_user() {
        role="$1"
        user="$2"
        file="$3"

        if [ ! -r "$file" ]; then
          echo "Secret file for ntfy user $user is missing or unreadable: $file" >&2
          return 1
        fi

        NTFY_PASSWORD=$(tr -d '\n' < "$file")
        export NTFY_PASSWORD

        if add_out=$($NTFY user -H "$DB" add --role="$role" "$user" 2>&1); then
          return 0
        fi
        if printf '%s\n' "$add_out" | grep -qi "already exists"; then
          $NTFY user -H "$DB" change-pass "$user"
        else
          printf '%s\n' "$add_out" >&2
          return 1
        fi
      }

      ensure_user user  alertmanager "${config.sops.secrets."ntfy/alertmanager_password".path}"
      $NTFY access -H "$DB" alertmanager alerts write-only

      ensure_user admin alex "${config.sops.secrets."ntfy/password".path}"
    '';
  };

  systemd.services.alertmanager-ntfy = {
    description = "Alertmanager to ntfy forwarder";
    wants = [
      "network-online.target"
      "sops-nix.service"
      "ntfy-sh.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
      "sops-nix.service"
      "ntfy-sh.service"
    ];
    # Webhook posts to obs-1 ntfy (the only instance).
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      config.sops.templates."alertmanager-ntfy.env".content
      "${./ntfy-group-webhook.py}"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./ntfy-group-webhook.py}";
      EnvironmentFile = config.sops.templates."alertmanager-ntfy.env".path;
      Restart = "always";
      User = "alertmanager-ntfy";
      Group = "alertmanager-ntfy";
    };
  };
}
