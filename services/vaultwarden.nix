{
  config,
  pkgs,
  ...
}:
{
  fleet.waitFor.postgres.vaultwarden.forServices = [ "vaultwarden.service" ];

  sops.secrets."vaultwarden/env" = {
    owner = "vaultwarden";
    restartUnits = [ "vaultwarden.service" ];
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
    openDefaultPorts = false; # Do not open 22000 globally; only tailscale0 is allowed below

    # The GUI has no authentication configured here, so it is not exposed to the
    # tailnet. Reach it with an SSH port-forward when it is needed.
    guiAddress = "127.0.0.1:8384";

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
        "proxmox-applications-1" = {
          id = "QYAQ4XF-ZTF2ANX-PVL3T7S-DU2A7OE-2AUFJPL-PA7DFBL-C36E7XF-OVBPZAZ";
          addresses = [ "tcp://proxmox-applications-1:22000" ];
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
            "proxmox-applications-1"
            "rpi4"
          ];
        };
      };
    };
  };

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  # Ensure systemd creates the custom state directory with the correct permissions
  systemd.services.syncthing.serviceConfig.StateDirectory = "syncthing-vaultwarden";

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      8222 # Vaultwarden (internal Caddy on apps-1; replica on rpi4)
      22000 # Syncthing sync (apps-1 <-> rpi4)
    ];
    allowedUDPPorts = [
      22000 # Syncthing sync
    ];
  };
}
