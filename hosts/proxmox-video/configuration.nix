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

  services.qemuGuest.enable = true;

  boot.kernelPackages = pkgs.linuxPackages;
  boot.extraModulePackages = [ pkgs.i915-sriov ];
  boot.kernelParams = [
    "snd-hda-intel.dmic_detect=0"

    "i915.enable_guc=3"
    "i915.force_probe=7d67"
    "module_blacklist=xe"
  ];

  networking.hostName = "proxmox-video";
  systemd.network.links."10-sriov" = {
    matchConfig.Driver = "iavf";
    linkConfig = {
      MACAddress = "82:cc:a5:22:e5:04";
    };
  };
  services.tailscale.port = lib.mkForce 41646;

  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/sda";
}
