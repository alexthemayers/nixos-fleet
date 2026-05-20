{ config, pkgs, ... }:

{
  services.resolved.enable = true;
  services.tailscale = {
    enable = true;
    extraDaemonFlags = [ "--debug=0.0.0.0:9251" ];
  };
  networking.firewall = {
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
  networking.nftables.enable = true;
  networking.nftables.tables.mangle = {
    family = "ip";
    content = ''
      chain output {
        type filter hook output priority mangle; policy accept;
        oifname "tailscale0" tcp flags syn tcp option maxseg size set 1232
      }
    '';
  };

  networking.networkmanager.dns = "systemd-resolved";
}
