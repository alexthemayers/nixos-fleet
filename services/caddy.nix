{
  config,
  pkgs,
  lib,
  ...
}:
let
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
        SecRule REQUEST_HEADERS:Upgrade "@streq websocket" "id:99999,phase:1,pass,t:none,t:lowercase,nolog,ctl:ruleEngine=Off"
        SecRule REQUEST_URI "@beginsWith /api/live/ws" "id:99998,phase:1,pass,t:none,nolog,ctl:ruleEngine=Off"
        ${customRules}
      `
    }
  '';

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
      events = 500;
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
      zone limit_vaultwarden_auth {
        key {remote_host}
        events 100
        window 1m
        match {
          not remote_ip 100.64.0.0/10 127.0.0.1 ::1
          path /identity/connect/token
        }
      }
      zone limit_vaultwarden_standard {
        key {remote_host}
        events 1000
        window 1m
        match {
          not remote_ip 100.64.0.0/10 127.0.0.1 ::1
        }
      }
      log_key
    }
  '';

  rateLimitFor =
    name: preset:
    if preset == "vaultwarden" then
      rateLimitVaultwarden
    else
      {
        standard = rateLimitStandard name;
        heavy = rateLimitHeavy name;
        ultraHeavy = rateLimitUltraHeavy name;
      }
      .${preset};

  mkAppProxy =
    app:
    let
      e = app.edge;
      dest =
        if e.upstream == "loopback" then
          "127.0.0.1:${toString app.port}"
        else if e.upstreamTls then
          "https://${app.host}:${toString app.port}"
        else
          "${app.host}:${toString app.port}";
      transport = e.dialTimeout != null || e.tlsInsecure;
      inner = lib.removeSuffix "\n" (
        lib.concatStrings [
          (lib.optionalString (e.flushInterval != null) "flush_interval ${e.flushInterval}\n")
          (lib.optionalString (e.lbTryDuration != null) "lb_try_duration ${e.lbTryDuration}\n")
          (lib.optionalString (e.lbTryInterval != null) "lb_try_interval ${e.lbTryInterval}\n")
          (lib.optionalString (e.healthUri != null) "health_uri ${e.healthUri}\n")
          (lib.optionalString (e.healthPort != null) "health_port ${toString e.healthPort}\n")
          (lib.optionalString (e.healthInterval != null) "health_interval ${e.healthInterval}\n")
          (lib.optionalString (e.healthTimeout != null) "health_timeout ${e.healthTimeout}\n")
          (lib.optionalString (e.healthStatus != null) "health_status ${e.healthStatus}\n")
          (lib.optionalString (e.failDuration != null) "fail_duration ${e.failDuration}\n")
          (lib.optionalString (e.maxFails != null) "max_fails ${toString e.maxFails}\n")
          (lib.optionalString (e.unhealthyStatus != null) "unhealthy_status ${e.unhealthyStatus}\n")
          (lib.optionalString transport ''
            transport http {
              ${lib.optionalString (e.dialTimeout != null) "dial_timeout ${e.dialTimeout}"}
              ${lib.optionalString e.tlsInsecure "tls_insecure_skip_verify"}
            }
          '')
        ]
      );
    in
    if inner == "" then
      "reverse_proxy ${dest}"
    else
      ''
        reverse_proxy ${dest} {
          ${inner}
        }
      '';

  mkEdgeVhost =
    name: app:
    let
      e = app.edge;
      zone = if e.rateLimitZone != null then e.rateLimitZone else name;
      proxy = mkAppProxy app;
      wafBlock = lib.optionalString e.waf (wafDetectionModeWith e.wafExtraDirectives);
      authBlock =
        if e.auth == "forward" then
          forwardAuth
        else if e.auth == "hybrid" then
          hybridForwardAuth
        else
          "";
      rateBlock = lib.optionalString (e.rateLimit != null) (rateLimitFor zone e.rateLimit);
      adminBlock = lib.optionalString (e.adminCidrPath != null) ''
        @adminCidr {
          path ${e.adminCidrPath}
          not remote_ip 100.64.0.0/10
        }
        abort @adminCidr
      '';
      headers = if e.securityHeaders == "loose" then looseSecurityHeaders else securityHeaders;
      bypass = e.wafBypassPaths != [ ] || e.wafBypassWebsockets;
    in
    {
      name = "${e.scheme}://${e.domain}";
      value = {
        extraConfig =
          if bypass then
            ''
              ${rateBlock}
              ${lib.optionalString (e.wafBypassPaths != [ ]) ''
                @bypassWafPaths path ${lib.concatStringsSep " " e.wafBypassPaths}
                handle @bypassWafPaths {
                  ${proxy}
                }
              ''}
              ${lib.optionalString e.wafBypassWebsockets ''
                @bypassWafSockets {
                  header Connection *Upgrade*
                  header Upgrade *websocket*
                }
                handle @bypassWafSockets {
                  ${proxy}
                }
              ''}
              handle {
                ${wafBlock}

                ${proxy}
              }

              ${commonLog}
              ${headers}
            ''
          else
            ''
              ${rateBlock}
              ${wafBlock}
              ${authBlock}
              ${adminBlock}

              ${proxy}

              ${commonLog}
              ${headers}
            '';
      };
    };

  registryVhosts = lib.listToAttrs (
    lib.mapAttrsToList mkEdgeVhost (lib.filterAttrs (_: app: app.edge != null) config.fleet.apps)
  );

  udpApps = lib.filterAttrs (_: app: app.udp != null) config.fleet.apps;
  layer4Config = lib.optionalString (udpApps != { }) ''
    layer4 {
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (_: app: ''
          udp/:${toString app.udp.listenPort} {
            route {
              proxy udp/${app.host}:${toString app.port}
            }
          }
        '') udpApps
      )}
    }
  '';
in
{
  config = lib.mkIf config.fleet.appOnThisHost.caddy {
    sops.secrets."oauth2-proxy/blackbox_token" = { };

    # BLACKBOX_TOKEN arrives as an EnvironmentFile, and environment variables are
    # only read at process start, so a rotated token needs a restart rather than a
    # config reload. Without restartUnits the new value sits on disk unused.
    sops.templates."caddy-env" = {
      restartUnits = [ "caddy.service" ];
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
    ]
    ++ lib.mapAttrsToList (_: app: app.udp.listenPort) udpApps;
    # Admin API stays on loopback (unauthenticated). Metrics are a separate HTTP
    # site on :2019, scraped over the tailnet (see the :2019 vhost below).
    networking.firewall.interfaces."tailscale0" = {
      allowedTCPPorts = [ 2019 ];
    };

    services.caddy = {
      enable = true;
      package = import ../config/caddy-package.nix { inherit pkgs; };
      email = "a.mayers102@gmail.com";
      globalConfig = ''
        order coraza_waf first
        order rate_limit before basicauth
        admin 127.0.0.1:2020 {
          origins 127.0.0.1:2020 localhost:2020
        }
        servers {
          timeouts {
            read_body 10s
            read_header 5s
          }
        }
        metrics {
          per_host
        }
        ${layer4Config}
      '';

      virtualHosts = {
        "http://:2019" = {
          extraConfig = ''
            metrics
          '';
        };
      }
      // registryVhosts;
    };

    assertions =
      let
        wafConfigs = lib.filter (s: lib.hasInfix "coraza_waf" s) (
          lib.mapAttrsToList (_: vh: vh.extraConfig or "") config.services.caddy.virtualHosts
        );
        notDetection = lib.filter (s: !(lib.hasInfix "SecRuleEngine DetectionOnly" s)) wafConfigs;
        blocking = lib.filter (s: lib.hasInfix "SecRuleEngine On" s) wafConfigs;
      in
      [
        {
          assertion = notDetection == [ ] && blocking == [ ];
          message = ''
            Coraza must stay SecRuleEngine DetectionOnly
            (docs/adr/2026-08-29-waf-detection-only.md). A vhost is missing
            DetectionOnly or sets SecRuleEngine On.
          '';
        }
      ];
  };
}
