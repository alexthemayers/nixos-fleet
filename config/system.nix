{ config, pkgs, ... }:

{
  nixpkgs.config = {
    allowUnfree = true;
  };
  nix = {
    settings = {
      substituters = [
        "http://proxmox-lb:8080/attic"
        "https://cache.nixos.org/"
        "https://nixos-raspberrypi.cachix.org"
      ];
      trusted-public-keys = [
        "attic:4/oEWZvm70jexTDGnT/Xvv2wlV3cE4utycLPZUSbmAw="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
      download-buffer-size = 1073741824; # 1024 MiB

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

  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    # Congestion control & Queueing
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";

    # Socket buffer increases for high-throughput, high-latency links
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";

    # Enable TCP MTU Probing to dynamically discover MTU black holes (common in VPN encapsulation)
    "net.ipv4.tcp_mtu_probing" = 1;

    # Backlog queue sizing for fast virtual interfaces
    "net.core.netdev_max_backlog" = 10000;

    # TCP Keepalive adjustments for database connections traversing firewalls
    "net.ipv4.tcp_keepalive_time" = 60;
    "net.ipv4.tcp_keepalive_intvl" = 10;
    "net.ipv4.tcp_keepalive_probes" = 6;
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
    fastfetch
    tmux
    jq
    tree
    mtr
    inetutils
    pciutils
  ];

  services.fstrim = {
    enable = true;
    interval = "weekly";
  };
}
