{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = {
    enable = true;
    email = "a.mayers102@gmail.com";

    globalConfig = ''
            # Enable Prometheus metrics (optional, but good for production)
            servers {
              metrics
      	max_header_size 5MB
            }
    '';

    virtualHosts."https://jellyfin.alexmayers.co.za" = {
      # The extraConfig block maps directly to what goes inside the 
      # domain block in a standard Caddyfile.
      extraConfig = ''
        # Proxy traffic to your backend service (e.g., running on port 8080)
        reverse_proxy containers:8096

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
        reverse_proxy containers:2283
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
  };
}
