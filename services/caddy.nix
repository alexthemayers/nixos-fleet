{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Unique hosts extracted from your Caddy configuration
  # Using the short-form names as they resolve via MagicDNS
  hosts = [
    "proxmox-video"
    "proxmox-observability"
    "proxmox-gitlab"
    "proxmox-gaming"
  ];
  mkKeepAlive = host: {
    "tailscale-ping-${host}" = {
      description = "Tailscale keep-alive ping for ${host}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.tailscale}/bin/tailscale ping -c 5 ${host}";
      };
    };
  };

  # Helper to create a timer for a specific host
  mkTimer = host: {
    "tailscale-ping-${host}" = {
      description = "Timer to trigger Tailscale keep-alive for ${host}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5"; # Runs every 5 minutes
        RandomizedDelaySec = 60; # Adds up to 60s of jitter to prevent thundering herd
        Persistent = true;
      };
    };
  };
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
        redir * /oauth2/start?rd=https://{host}{uri}
      }
    }

    # 3. Route the callback and auth endpoints directly to oauth2-proxy
    reverse_proxy /oauth2/* 127.0.0.1:4180
  '';
in
{
  systemd.services = lib.foldl' (acc: host: acc // mkKeepAlive host) { } hosts;
  systemd.timers = lib.foldl' (acc: host: acc // mkTimer host) { } hosts;

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
          ${forwardAuth}
          reverse_proxy proxmox-observability:3000
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://prometheus.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-observability:9090
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://alertmanager.alexmayers.co.za" = {
        extraConfig = ''
          ${forwardAuth}
          reverse_proxy proxmox-observability:9093
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://gitlab.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:8080
          encode zstd gzip
          log { format console }
          ${securityHeaders}
        '';
      };

      "https://identity.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-gitlab:7777 rpi4:7777 {
            # TODO: Add health checks
            lb_policy first
          }
          encode zstd gzip
          log { format console }
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
            # TODO: Add health checks
            lb_policy first
          }
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
  };
}
