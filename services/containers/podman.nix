{ config, lib, pkgs, ... }:
{

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
  ];
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  users.users.alex = {
    extraGroups = [
      "podman"
    ];
  };
  networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 ];
  networking.firewall.interfaces."podman*".allowedTCPPorts = [ 53 ];
}