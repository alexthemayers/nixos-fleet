{
  config,
  pkgs,
  lib,
  ...
}:

{
  nixpkgs.config = {
    allowUnfree = true;
  };
  nix = {
    settings = {
      # Fleet hosts substitute from atticd on the monolithic node, through
      # attic-nar-proxy on :8080 (307→200 for single-chunk NARs). Multi-chunk
      # NARs still truncate through the LB Caddy hop, so this stays on db-1.
      substituters = lib.mkForce [
        "http://proxmox-db-1:8080/attic"
      ];
      trusted-public-keys = lib.mkForce [
        "attic:4/oEWZvm70jexTDGnT/Xvv2wlV3cE4utycLPZUSbmAw="
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

  environment.systemPackages = with pkgs; [
    cloud-utils
    gawk
    git
    rsync
    wget
    gnumake
    fastfetch
    tmux
    jq
    tree
    mtr
    inetutils
    pciutils
    btop
  ];

  services.fstrim.enable = true;
}
