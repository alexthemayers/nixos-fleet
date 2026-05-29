{ config, pkgs, ... }:

{
  nixpkgs.config = {
    allowUnfree = true;
  };
  nix = {
    settings = {
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"

        "https://nixos-raspberrypi.cachix.org"

      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];

      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "@wheel" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
    };
  };

  time.timeZone = "Africa/Johannesburg";
  i18n.defaultLocale = "en_US.UTF-8";

  networking = {
    useNetworkd = true;
    useDHCP = true;
  };

  system = {
    autoUpgrade.enable = false;
  };

  environment.systemPackages = with pkgs; [
    cloud-utils
    gawk
    git
    neovim
    wget
    gnumake
    tmux
    jq
    tree
    mtr
    inetutils
    pciutils
  ];
}
