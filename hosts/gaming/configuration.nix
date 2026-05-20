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
    nvtopPackages.amd
    btop-rocm
    libva-utils
  ];

  security.rtkit.enable = true;
  system.autoUpgrade.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "snd-hda-intel.dmic_detect=0"
    "amd_pstate=guided"
  ];
  # Specific to AMD CPU
  boot.blacklistedKernelModules = [ "k10temp" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];
  boot.kernelModules = [ "zenpower" ];

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "schedutil";

  networking.networkmanager = {
    enable = true;
    wifi = {
      backend = "wpa_supplicant";
      powersave = false;
    };
  };

  networking.hostName = "gaming";

  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/nvme0n1";
}
