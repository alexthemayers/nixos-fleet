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
    # 1. Match everything EXCEPT the OAuth2 endpoints and the Blackbox bypass header
    @requireAuth {
      not path /oauth2/*
      not header X-Blackbox-Token "{$BLACKBOX_TOKEN}"
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
  sops.secrets."oauth2-proxy/blackbox_token" = { };

  sops.templates."caddy-env" = {
    content = ''
      BLACKBOX_TOKEN="${config.sops.placeholder."oauth2-proxy/blackbox_token"}"
    '';
    owner = "caddy";
    group = "caddy";
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = [ config.sops.templates."caddy-env".path ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443 # quic
    30000 # luanti
  ];
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      2019 # admin interface
    ];
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/mholt/caddy-l4@v0.1.1" ];
      hash = "sha256-/ebF+f235CR36VKfCITtQWXr9wojpgsszxxnZ8HeCd0=";
    };
    email = "a.mayers102@gmail.com";
    globalConfig = ''
      admin 0.0.0.0:2019
      metrics {
        per_host
      }
      layer4 {
        udp/:30000 {
          route {
            proxy udp/proxmox-gaming:30000
          }
        }
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
          reverse_proxy proxmox-video:8096 {
            flush_interval -1
          }
          encode zstd gzip
          header -Alt-Svc
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
          reverse_proxy proxmox-observability:9090 rpi4:9090 {
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
          reverse_proxy proxmox-gitlab:8080 {
            flush_interval -1
          }
          encode zstd gzip
          log { format json }
          ${securityHeaders}
        '';
      };

      "https://coder.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gaming:7080
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

      "https://paperless.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-gitlab:28981
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

      "https://s3.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-db:3902 rpi4:3902 {
            lb_policy first
            lb_try_duration 5s
            health_uri /health
            health_port 3903
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
