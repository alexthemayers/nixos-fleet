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
      X-Frame-Options "SAMEORIGIN"
      Referrer-Policy "strict-origin-when-cross-origin"
    }
  '';
  forwardAuth = ''
    # 1. Match everything EXCEPT the OAuth2 endpoints
    @requireAuth {
      not path /oauth2/*
    }

    # 2. Apply forward_auth ONLY to those matched routes
    forward_auth @requireAuth 127.0.0.1:4180 {
      uri /oauth2/auth
      
      # Extract headers provided by oauth2-proxy and pass them to the backend
      copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      
      # Catch the headless 401 from OAuth2-Proxy and trigger the Keycloak redirect
      @error status 401
      handle_response @error {
        redir * https://auth.alexmayers.co.za/oauth2/start?rd=https://{host}{uri}
      }
    }

    # 3. Route the callback and auth endpoints directly to oauth2-proxy
    reverse_proxy /oauth2/* 127.0.0.1:4180
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

    virtualHosts = {
      "https://auth.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:4180
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://jellyfin.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-video:8096
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://immich.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-video:2283 {
            flush_interval -1
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://grafana.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-observability:3000 rpi4:3000 {
            lb_policy first
            health_uri /api/health
            health_interval 5s
            health_timeout 2s
            health_status 200
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://prometheus.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-observability:9090 rpi:9090 {
            lb_policy first
            health_uri /-/healthy
            health_interval 5s
            health_timeout 2s
            health_status 2xx
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://alertmanager.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-observability:9093 rpi4:9093 {
            lb_policy first
            health_uri /-/healthy
            health_interval 5s
            health_timeout 2s
            health_status 2xx
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://gitlab.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:8080
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://budget.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-gitlab:5006
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://identity.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:7777 rpi4:7777 {
            lb_policy first
            lb_try_duration 5s
            health_uri /health/ready
            health_port 9000
            health_interval 5s
            health_timeout 2s
            health_status 2xx
            fail_duration 10s
            max_fails 1
            unhealthy_status 5xx
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://vaultwarden.alexmayers.co.za" = {
        extraConfig = ''
          @vaultwardenAdmin {
            path /admin*
            not remote_ip 100.64.0.0/10
          }
          abort @vaultwardenAdmin
          reverse_proxy proxmox-gitlab:8222 rpi4:8222 {
            lb_policy first
            lb_try_duration 5s
            health_uri /alive
            health_interval 5s
            health_timeout 2s
            health_status 200
            fail_duration 10s
            max_fails 1
            unhealthy_status 5xx
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://tasks.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:3456
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://proxmox.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy https://proxmox:8006 {
            transport http {
              tls_insecure_skip_verify
            }
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://truenas.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy http://truenas-scale:80
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };
    };
  };
}
