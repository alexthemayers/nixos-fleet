{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.openarena.enable = true;
  services.openarena.openPorts = true;
  services.openarena.extraFlags = [
    "+set sv_hostname NixOS OpenArena"
  ];
  networking.firewall.allowedUDPPorts = [
    27960
    27961
    27962
    27963
  ];
}
