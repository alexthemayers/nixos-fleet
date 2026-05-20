{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # Include the results of the hardware scan.
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Bootloader.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    nvtopPackages.intel
    btop
    libva-utils
  ];

  security.rtkit.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "snd-hda-intel.dmic_detect=0"
  ];

  networking.hostName = "proxmox-video";

  users = {
    users.containers = {
      isSystemUser = true;
      group = "render";
      description = "container runner";
      shell = pkgs.zsh;
      uid = 3000;
    };
  };

  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/sda";
}
