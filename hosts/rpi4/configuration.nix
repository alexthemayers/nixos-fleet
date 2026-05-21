{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    btop
  ];

  networking.hostName = "rpi4";
  services.tailscale.port = lib.mkForce 41647;

  system.stateVersion = "25.11";
}
