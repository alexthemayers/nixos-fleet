{
  modulesPath,
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
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.qemuGuest.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  system.stateVersion = "25.11";

  # Root SSH is key-only. Do not advertise 22 on the public NIC; CI and
  # operators reach this VM over Tailscale. The provider console is the
  # out-of-band path if the tailnet is down.
  services.openssh.openFirewall = lib.mkForce false;
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 ];

  # Cloud VMs are 1–2 GiB. A memory spike (nix-daemon, Attic fill backends)
  # used to go straight to the OOM killer. zram takes the first overflow;
  # the disk file is the last resort. Deploys still build on the deployer
  # (see mkNode in flake.nix).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2048;
    }
  ];
  boot.kernel.sysctl."vm.swappiness" = 10;

  # Fleet default is 1 GiB (config/system.nix). That allocation alone OOMs
  # these VMs if nix-daemon runs.
  nix.settings.download-buffer-size = lib.mkForce 67108864; # 64 MiB

  # Uncapped journals were 668M on disk / ~100M RSS on xcloud-postgres.
  services.journald.extraConfig = ''
    SystemMaxUse=64M
    RuntimeMaxUse=32M
    SystemKeepFree=128M
  '';
}
