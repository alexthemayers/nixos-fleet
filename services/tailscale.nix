{ config, pkgs, ... }:

{
  services.resolved.enable = true;
  services.tailscale = {
    enable = true;
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
  systemd.services.tailscale-metrics = {
    description = "Tailscale Client Metrics";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscale web --readonly --listen 0.0.0.0:9251";
      Restart = "on-failure";
      Type = "simple";
    };
  };

  networking.networkmanager.dns = "systemd-resolved";
}
