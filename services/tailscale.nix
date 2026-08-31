{ config, pkgs, ... }:

{
  # Deliberately *no* restartUnits here, unlike every other secret in the tree.
  # authKeyFile is only read when a node first authenticates to the tailnet;
  # after that the node has its own node key and the auth key is irrelevant, so
  # restarting buys nothing. It would also drop tailscale0 on every host at once
  # -- including the connection performing the deploy, since deploys run over the
  # tailnet.
  sops.secrets."tailscale/auth_key" = { };
  services.resolved.enable = true;
  services.tailscale = {
    authKeyFile = config.sops.secrets."tailscale/auth_key".path;
    enable = true;
    port = 41642;
    interfaceName = "tailscale0";
    extraUpFlags = [ "--hostname=${config.networking.hostName}" ];
  };
  networking.firewall = {
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };
  networking.nftables.enable = true;
  networking.nftables.tables.mangle = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority mangle; policy accept;
        iifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
        oifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
      }
      chain output {
        type filter hook output priority mangle; policy accept;
        oifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
      }
    '';
  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    9251 # tailscale web --readonly (Prometheus scrape)
  ];

  systemd.services.tailscale-metrics = {
    description = "Tailscale Client Metrics";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscale web --readonly --listen 0.0.0.0:9251";
      Restart = "always";
      RestartSec = "10s";
      Type = "simple";
    };
  };

  environment.systemPackages = [ pkgs.ethtool ];
  systemd.services.tailscale-udp-optimize = {
    description = "Optimize network interface for Tailscale UDP throughput";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      pkgs.gawk
      pkgs.iproute2
      pkgs.ethtool
    ];

    serviceConfig = {
      Type = "oneshot";
      # This script finds the interface handling the default internet route
      ExecStart = pkgs.writeShellScript "tailscale-udp-optimize" ''
        # Wait up to 15 seconds for the default route to appear
        for i in {1..15}; do
          INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')
          if [ -n "$INTERFACE" ]; then
            break
          fi
          sleep 1
        done

        if [ -n "$INTERFACE" ]; then
          echo "Optimizing interface: $INTERFACE"
          # Tailscale's own guidance is rx-udp-gro-forwarding on AND
          # rx-gro-list off. Enabling both has been reported to corrupt or drop
          # forwarded UDP, which is precisely the traffic this is meant to speed up.
          ethtool -K "$INTERFACE" rx-udp-gro-forwarding on rx-gro-list off

          # Ring buffer resizing is unsupported on some virtio NICs, so a
          # failure here is tolerated, but it is logged rather than swallowed.
          if ! ethtool -G "$INTERFACE" rx 1024 tx 1024; then
            echo "Note: $INTERFACE does not support ring buffer resizing; continuing." >&2
          fi
        else
          echo "Error: Could not automatically detect physical network interface." >&2
          exit 1
        fi
      '';
      RemainAfterExit = true;
    };
  };
}
