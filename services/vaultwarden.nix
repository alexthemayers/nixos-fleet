{ config, pkgs, ... }:
{
  sops.secrets."vaultwarden/env" = {
    owner = "vaultwarden";
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = config.sops.secrets."vaultwarden/env".path;
    config = {
      # https://github.com/dani-garcia/vaultwarden/blob/1.36.0/.env.template
      DOMAIN = "https://vaultwarden.alexmayers.co.za";
      ROCKET_PORT = 8222;
      ROCKET_ADDRESS = "0.0.0.0";
      SIGNUPS_ALLOWED = false;
      EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
    };
  };

  services.syncthing = {
    enable = true;
    user = "vaultwarden";
    group = "vaultwarden";
    dataDir = "/var/lib/vaultwarden";
    configDir = "/var/lib/syncthing-vaultwarden";
    openDefaultPorts = false; # Do not open ports globally; trust tailscale0 instead

    guiAddress = "0.0.0.0:8384"; # Accessible over Tailscale (secured by firewall)

    overrideDevices = true;
    overrideFolders = true;

    settings = {
      options = {
        globalAnnounceEnabled = false; # Disable global discovery
        localAnnounceEnabled = false; # Disable local discovery (use Tailscale hostnames instead)
        relaysEnabled = false; # Disable relaying
        urAccepted = -1; # Disable usage reporting
      };

      devices = {
        "proxmox-gitlab" = {
          id = "HOVOISJ-BYRI5QG-RMRIOIX-FWH7UP4-SOY3J7E-QBJBASQ-SEAE2S7-NQS4KAB";
          addresses = [ "tcp://proxmox-gitlab:22000" ];
        };
        "rpi4" = {
          id = "H43JR7F-TUWRBCB-NAPJFTP-LI7B2OW-NABHYKY-I2ZZ35W-BL34MBR-JFSZVAW";
          addresses = [ "tcp://rpi4:22000" ];
        };
      };

      folders = {
        "vaultwarden-state" = {
          id = "vaultwarden-state";
          path = "/var/lib/vaultwarden";
          devices = [
            "HOVOISJ-BYRI5QG-RMRIOIX-FWH7UP4-SOY3J7E-QBJBASQ-SEAE2S7-NQS4KAB"
            "H43JR7F-TUWRBCB-NAPJFTP-LI7B2OW-NABHYKY-I2ZZ35W-BL34MBR-JFSZVAW"
          ];
        };
      };
    };
  };

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  # Ensure systemd creates the custom state directory with the correct permissions
  systemd.services.syncthing.serviceConfig.StateDirectory = "syncthing-vaultwarden";
}
