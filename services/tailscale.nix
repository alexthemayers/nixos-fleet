{ config, pkgs, ... }:

{
  sops.secrets."tailscale/auth_key" = { };
  services.resolved.enable = true;
  services.tailscale = {
    authKeyFile = config.sops.secrets."tailscale/auth_key".path;
    enable = true;
    port = 41642;
    interfaceName = "tailscale0";
  };
  networking.firewall = {
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
  networking.nftables.enable = true;
  networking.nftables.tables.mangle = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority mangle; policy accept;
        oifname "tailscale0" tcp flags syn tcp option maxseg size set 1232
      }
    '';
  };
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

  networking.networkmanager.dns = "systemd-resolved";

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
          ethtool -K "$INTERFACE" rx-udp-gro-forwarding on rx-gro-list on
        else
          echo "Error: Could not automatically detect physical network interface." >&2
          exit 1
        fi
      '';
      RemainAfterExit = true;
    };
  };
}
