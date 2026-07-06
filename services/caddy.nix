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
      Content-Security-Policy "default-src 'self' https: wss: data: blob: 'unsafe-inline' 'unsafe-eval'; frame-ancestors 'self';"
      Permissions-Policy "geolocation=(), microphone=(), camera=()"
      -Server
    }
  '';

  looseSecurityHeaders = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      -Server
    }
  '';

  wafDetectionModeWith = customRules: ''
    coraza_waf {
      load_owasp_crs
      directives `
        Include @coraza.conf-recommended
        Include @crs-setup.conf.example
        Include @owasp_crs/*.conf
        SecRuleEngine DetectionOnly
        SecRule REQUEST_HEADERS:Upgrade "@streq websocket" "id:99999,phase:1,pass,t:none,nolog,ctl:ruleEngine=Off"
        ${customRules}
      `
    }
  '';

  wafDetectionMode = wafDetectionModeWith "";

  commonLog = ''
    log {
      format filter {
        wrap json
        fields {
          request>headers>X-Blackbox-Token delete
        }
      }
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
  hybridForwardAuth = ''
    # 1. Handle API Traffic (Headless -> No Redirect)
    @apiAuth {
      path /api/*
      not path /oauth2/*
      not header X-Blackbox-Token "{$BLACKBOX_TOKEN}"
    }
    forward_auth @apiAuth 127.0.0.1:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
    }

    # 2. Handle UI Traffic (Browser -> Redirect to Keycloak)
    @uiAuth {
      not path /api/* /oauth2/*
      not header X-Blackbox-Token "{$BLACKBOX_TOKEN}"
    }
    forward_auth @uiAuth 127.0.0.1:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      
      @error status 401
      handle_response @error {
        redir * https://auth.alexmayers.co.za/oauth2/start?rd=https://{host}{uri}
      }
    }

    # 3. Route oauth2-proxy internals
    reverse_proxy /oauth2/* 127.0.0.1:4180
  '';
  apiForwardAuth = ''
    @requireAuth {
      not path /oauth2/*
      not header X-Blackbox-Token "{$BLACKBOX_TOKEN}"
    }
    forward_auth @requireAuth 127.0.0.1:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username Authorization
    }
    reverse_proxy /oauth2/* 127.0.0.1:4180
  '';

  rateLimitConfig = name: { events, window }: ''
    rate_limit {
      zone limit_${name} {
        key {remote_host}
        events ${toString events}
        window ${window}
        match {
          not remote_ip 100.64.0.0/10 127.0.0.1 ::1
        }
      }
      log_key
    }
  '';

  rateLimitStandard =
    name:
    rateLimitConfig name {
      events = 200;
      window = "1m";
    };
  rateLimitHeavy =
    name:
    rateLimitConfig name {
      events = 1000;
      window = "1m";
    };
  rateLimitUltraHeavy =
    name:
    rateLimitConfig name {
      events = 2000;
      window = "1m";
    };

  rateLimitVaultwarden = ''
    rate_limit {
      zone limit_vaultwarden_strict {
        key {remote_host}
        events 30
        window 1m
        match {
          not remote_ip 100.64.0.0/10 127.0.0.1 ::1
          path /admin* /api* /identity*
        }
      }
      zone limit_vaultwarden_standard {
        key {remote_host}
        events 200
        window 1m
        match {
          not remote_ip 100.64.0.0/10 127.0.0.1 ::1
          not path /admin* /api* /identity*
        }
      }
      log_key
    }
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
  systemd.services.caddy.wants = [ "network-online.target" ];
  systemd.services.caddy.after = [
    "network-online.target"
    "tailscaled.service"
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443 # quic
    27960 # openarena
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
      plugins = [
        "github.com/corazawaf/coraza-caddy/v2@v2.5.0"
        "github.com/mholt/caddy-l4@v0.1.1"
        "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260612195517-5625512f24f6"
      ];
      hash = "sha256-3lGfwEVaEH4Z+sa44Kqst+b+m0KhX8Aphd+8W6deEoA=";
    };
    email = "a.mayers102@gmail.com";
    globalConfig = ''
      order coraza_waf first
      order rate_limit before basicauth
      admin 0.0.0.0:2019
      servers {
        timeouts {
          read_body 10s
          read_header 5s
          write 30s
          idle 2m
        }
      }
      metrics {
        per_host
      }
      layer4 {
        udp/:27960 {
          route {
            proxy udp/proxmox-gaming:27960
          }
        }
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
          ${rateLimitStandard "auth"}
          ${wafDetectionMode}
          reverse_proxy 127.0.0.1:4180
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://jellyfin.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "jellyfin"}
          ${wafDetectionMode}
          reverse_proxy proxmox-video:8096 {
            flush_interval -1
          }
          encode zstd gzip
          header -Alt-Svc
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://immich.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "immich"}
          ${wafDetectionMode}
          reverse_proxy proxmox-video:2283 {
            flush_interval -1
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://grafana.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "grafana"}
          ${wafDetectionModeWith ''
            SecRule REQUEST_URI "@beginsWith /api/ds/query" "id:10001,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932235,ctl:ruleRemoveById=942100,ctl:ruleRemoveById=942550"
            SecRule REQUEST_URI "@beginsWith /api/datasources" "id:10002,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932235"
            SecRule REQUEST_URI "@beginsWith /explore" "id:10003,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932230,ctl:ruleRemoveById=932250"
          ''}
          ${forwardAuth}

          reverse_proxy proxmox-observability:3000 rpi4:3000 {
            lb_policy first
            health_uri /api/health
            flush_interval -1
            health_interval 5s
            health_timeout 2s
            health_status 200
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://mimir.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitUltraHeavy "mimir"}
          ${apiForwardAuth}

          reverse_proxy proxmox-observability:9009 rpi4:9009 {
            lb_policy first
            health_uri /ready
            health_interval 5s
            health_timeout 2s
            health_status 200
          }

          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://loki.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "loki"}
          ${apiForwardAuth}

          reverse_proxy proxmox-observability:3100 rpi4:3100 {
            lb_policy first
            health_uri /ready
            health_interval 5s
            health_timeout 2s
            health_status 200
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://prometheus.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "prometheus"}
          ${hybridForwardAuth}

          reverse_proxy proxmox-observability:9090 rpi4:9090 {
            lb_policy first
            health_uri /-/healthy
            health_interval 5s
            health_timeout 2s
            health_status 2xx
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://alertmanager.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "alertmanager"}
          ${hybridForwardAuth}
          reverse_proxy proxmox-observability:9093 rpi4:9093 {
            lb_policy first
            health_uri /-/healthy
            health_interval 5s
            health_timeout 2s
            health_status 2xx
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://gitlab.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "gitlab"}
          ${wafDetectionModeWith ''
            SecRule REQUEST_URI "@contains .git/" "id:10301,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=930130,ctl:ruleRemoveById=920420"
            SecRule REQUEST_URI "@beginsWith /api/graphql" "id:10302,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=942290,ctl:ruleRemoveById=932160,ctl:ruleRemoveById=932235"
            SecRule REQUEST_URI "@streq /api/server/version" "id:10303,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=920420"
          ''}

          reverse_proxy proxmox-gitlab:8080 {
            flush_interval -1
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://registry.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitUltraHeavy "registry"}
          ${wafDetectionMode}

          reverse_proxy http://proxmox-gitlab:5005
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://coder.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "coder"}
          ${wafDetectionMode}
          reverse_proxy proxmox-gaming:7080 {
            flush_interval -1
          }
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://budget.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "budget"}
          ${forwardAuth}

          reverse_proxy proxmox-gitlab:5006
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://paperless.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "paperless"}
          ${forwardAuth}
          reverse_proxy proxmox-gitlab:28981
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://identity.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "identity"}
          ${wafDetectionMode}

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
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://vaultwarden.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitVaultwarden}
          ${wafDetectionMode}

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
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://s3.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitUltraHeavy "s3"}
          ${wafDetectionMode}

          reverse_proxy /health proxmox-db:3903 rpi4:3903 {
            lb_policy first
          }

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
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://tasks.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "tasks"}
          ${wafDetectionMode}

          reverse_proxy proxmox-gitlab:3456
          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };

      "https://proxmox.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "proxmox"}
          ${forwardAuth}

          reverse_proxy https://proxmox:8006 {
            flush_interval -1
            transport http {
              tls_insecure_skip_verify
            }
          }

          encode zstd gzip
          ${commonLog}
          ${looseSecurityHeaders}
        '';
      };

      "https://truenas.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitHeavy "truenas"}
          ${forwardAuth}
          reverse_proxy http://truenas-scale:80 {
            flush_interval -1
          }
          encode zstd gzip
          ${commonLog}
          ${looseSecurityHeaders}
        '';
      };

      "https://ntfy.alexmayers.co.za" = {
        extraConfig = ''
          ${rateLimitStandard "ntfy"}
          ${wafDetectionMode}

          reverse_proxy proxmox-observability:2586 rpi4:2586 {
            lb_policy first
            lb_try_duration 5s
            health_uri /v1/health
            health_interval 5s
            health_timeout 2s
            health_status 200
            fail_duration 10s
            max_fails 1
            unhealthy_status 5xx
          }

          encode zstd gzip
          ${commonLog}
          ${securityHeaders}
        '';
      };
    };
  };
}
