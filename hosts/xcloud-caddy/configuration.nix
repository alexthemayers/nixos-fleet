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

  networking.hostName = "xcloud-caddy";
  networking.interfaces.ens3.mtu = 1500;

  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.iperf3
    pkgs.neovim
    pkgs.btop
  ];

  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  system.stateVersion = "25.11";

  # Custom Options
  fleet.disk.path = "/dev/vda";
}
