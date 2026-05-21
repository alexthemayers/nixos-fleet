{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.qemuGuest.enable = true;

  networking.hostName = "xcloud-postgres";

  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.iperf3
    pkgs.neovim
    pkgs.btop
  ];

  system.stateVersion = "25.11";
}
