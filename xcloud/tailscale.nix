{ config, pkgs, ... }:

{
  networking.firewall = {
    allowedUDPPorts = [ 41641 ];
    # This helps when one node is behind a "hard" NAT (like some ISPs/LTE)
    checkReversePath = "loose";
  };

  services.tailscale.enable = true;
}
