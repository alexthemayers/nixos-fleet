{ ... }:
{
  networking.hostName = "rpi4";
  system.stateVersion = "25.11";

  # aarch64 paths are not all on cache.nixos.org. system.nix already
  # mkForce's the public cache and its key; these add the Pi cachix.
  nix.settings.extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  ];
}
