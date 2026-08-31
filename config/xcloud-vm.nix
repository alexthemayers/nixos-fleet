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

  # 1.9 GiB of RAM and no swap: a memory spike goes straight to the OOM killer,
  # which has picked nix-daemon during deploys. Swap makes that a slowdown
  # rather than a killed process. Deploys build on the deployer (see mkNode in
  # flake.nix); this is the second line of defence.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2048;
    }
  ];
}
