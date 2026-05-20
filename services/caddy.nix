{
  config,
  lib,
  pkgs,
  ...
}:
let
  # This enforces strict HTTPS, prevents mime-sniffing, and blocks clickjacking.
  securityHeaders = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "DENY"
      Referrer-Policy "strict-origin-when-cross-origin"
    }
  '';
in
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443 # quic
    27960 # openarena
  ];
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      2019 # admin interface
    ];
  };

  services.caddy = {
    enable = true;
    email = "a.mayers102@gmail.com";
    globalConfig = ''
      admin 0.0.0.0:2019
      metrics {
        per_host
      }
    '';
    #     package = pkgs.caddy.withPlugins {
    #       plugins = [ "github.com/mholt/caddy-l4@v0.1.0" ];
    #       hash = "sha256-/AxtpMmEvYvbxTSOvANv5wRx/6shTYi/l29L7kRTgE4=";
    #     };
    #     settings = {
    #   apps.layer4.servers.openarena = {
    #     listen = [ ":27960" ];
    #     routes = [
    #       {
    #         handle = [
    #           {
    #             handler = "proxy";
    #             upstreams = [
    #               {
    #                 # Use your Proxmox VM's MagicDNS name here
    #                 dial = [ "open-arena.your-tailnet.ts.net:27960" ];
    #               }
    #             ];
    #           }
    #         ];
    #       }
    #     ];
    #   };
    # };

    virtualHosts = {
      "https://jellyfin.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-video:8096
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://immich.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-video:2283 {
            flush_interval -1
          }
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://grafana.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability:3000
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://identity.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:7777
          encode zstd gzip
          log { format console }
        '';
        #          ${securityHeaders}
      };

      "https://vaultwarden.alexmayers.co.za" = {
        extraConfig = ''
          @vaultwardenAdmin {
            path /admin*
            not remote_ip 100.64.0.0/10
          }
          abort @vaultwardenAdmin
          reverse_proxy proxmox-gitlab:8222
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://quake.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy http://proxmox-gaming.bee-phrygian.ts.net
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };
    };
    # virtualHosts."https://foundry.alexmayers.co.za" = {
    #   # The extraConfig block maps directly to what goes inside the
    #   # domain block in a standard Caddyfile.
    #   extraConfig = ''
    #     # Proxy traffic to your backend service (e.g., running on port 8080)
    #     reverse_proxy proxmox-gaming:30000

    #     # Sane Default: Enable zstd and gzip compression for performance
    #     encode zstd gzip

    #     # Sane Default: Structured JSON logging.
    #     # On NixOS, Caddy writes stdout/stderr to the systemd journal by default.
    #     # This directive ensures requests are properly logged and formatted.
    #     log {
    #       format console
    #     }

    #     # Security headers (Optional but highly recommended for production)
    #     header {
    #       Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    #       X-Content-Type-Options "nosniff"
    #       X-Frame-Options "DENY"
    #       Referrer-Policy "strict-origin-when-cross-origin"
    #     }
    #   '';
    # };
  };
}
