{ config, pkgs, ... }:
{
  xdg.portal.enable = true;
  environment.systemPackages = with pkgs; [
    xdg-utils
    adwaita-icon-theme
  ];
  users.users.alex.extraGroups = [
    "video"
    "input"
  ];
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    plasma-browser-integration
    elisa
  ];
}
