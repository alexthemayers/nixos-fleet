{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    80
    443
    2019 # metrics
  ];
  networking.firewall.allowedUDPPorts = [
    443 # quic
    27960 # openarena
  ];

  services.caddy = {
    enable = true;
    email = "a.mayers102@gmail.com";
    globalConfig = ''
      admin 0.0.0.0:2019
      metrics {
        per_host
      }
      servers {
        max_header_size 5MB
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

    virtualHosts."https://jellyfin.alexmayers.co.za" = {
      # The extraConfig block maps directly to what goes inside the
      # domain block in a standard Caddyfile.
      extraConfig = ''
        # Proxy traffic to your backend service (e.g., running on port 8080)
        reverse_proxy proxmox-video:8096

        # Sane Default: Enable zstd and gzip compression for performance
        encode zstd gzip

        # Sane Default: Structured JSON logging. 
        # On NixOS, Caddy writes stdout/stderr to the systemd journal by default.
        # This directive ensures requests are properly logged and formatted.
        log {
          format console
        }

        # Security headers (Optional but highly recommended for production)
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      '';
    };
    virtualHosts."https://immich.alexmayers.co.za" = {
      extraConfig = ''
        reverse_proxy proxmox-video:2283
        encode zstd gzip

        log {
          format console
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      '';
    };
    virtualHosts."https://grafana.alexmayers.co.za" = {
      extraConfig = ''
        reverse_proxy proxmox-observability:3000
        encode zstd gzip

        log {
          format console
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      '';
    };
    virtualHosts."https://vaultwarden.alexmayers.co.za" = {
      extraConfig = ''
        reverse_proxy proxmox-gitlab:8088
        encode zstd gzip

        log {
          format console
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      '';
    };
    virtualHosts."https://quake.alexmayers.co.za" = {
      extraConfig = ''
        header Content-Security-Policy "upgrade-insecure-requests"
        reverse_proxy https://proxmox-gaming.bee-phrygian.ts.net
      '';
    };
    virtualHosts."quake.alexmayers.co.za:27960" = {
      extraConfig = ''
        reverse_proxy http://proxmox-gaming.bee-phrygian.ts.net:27960 {
          transport http {
          }
        }
      '';
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
