{ config, pkgs, ... }:
{
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  security.audit.enable = true;
}
