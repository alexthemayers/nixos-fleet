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
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    btop
  ];

  # Allow arm64 emulation for execution of build steps that require arm64 instructions
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking.hostName = "proxmox-applications-2";
  systemd.network.links."10-sriov" = {
    matchConfig.Driver = "iavf";
    linkConfig = {
      MACAddress = "82:cc:a5:22:e5:02";
    };
  };
  services.tailscale.port = lib.mkForce 41644;

  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/sda";

  systemd.services.paperless-consumer.enable = false;
  systemd.services.paperless-scheduler.enable = false;
  systemd.services.paperless-task-queue.enable = false;
  systemd.services.paperless-create-dirs.enable = false;
}
