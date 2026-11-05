{
  config,
  pkgs,
  lib,
  ...
}:
let
  app = config.fleet.apps.openarena;
in
{
  config = lib.mkIf config.fleet.appOnThisHost.openarena {
    services.openarena.enable = true;
    # openPorts opens 27960/udp on every interface. Players reach this host
    # through xcloud-caddy's layer-4 proxy over the tailnet, so
    # only tailscale0 needs it.
    services.openarena.openPorts = false;
    networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ app.port ];
    services.openarena.extraFlags = [
      "+set sv_hostname \"Alex's OpenArena\""
      "+map oa_dm1"
    ];

    fileSystems."/mnt/nfs/openarena" = {
      device = "truenas-scale:/mnt/ssd/openarena";
      fsType = "nfs";
      options = import ../config/nfs-mount.nix "openarena" [ ];
    };

    fleet.waitForHost.openarena.host = "truenas-scale";

    systemd.services.openarena = {
      serviceConfig = {
        RequiresMountsFor = [ "/mnt/nfs/openarena" ];
        BindPaths = [ "/mnt/nfs/openarena:/var/lib/openarena" ];
      };
    };

    fleet.alwaysRestart = [ app.unit ];
  };
}
