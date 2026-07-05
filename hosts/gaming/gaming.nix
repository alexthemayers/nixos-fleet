{ config, pkgs, ... }:
{
  users.users.alex.extraGroups = [
    "gamemode"
    "audio"
    "video"
    "cpu"
  ];
  environment.systemPackages = with pkgs; [
    # Performance and compatibility layers
    gamemode
    mangohud
    dxvk
    protonup-qt

    # just keep them all, they work
    wineWow64Packages.waylandFull
    wineWow64Packages.staging
    winetricks

    discord
  ];
  programs = {
    steam.enable = true;
    gamemode.enable = true;
    ut2004.enable = true;

    # TODO: not sure if I need this right now (https://wiki.nixos.org/wiki/Appimage)
    appimage = {
      enable = true;
      binfmt = true;
      package = pkgs.appimage-run.override { extraPkgs = pkgs: [ ]; };
    };
  };
  services.ratbagd.enable = true;
}
