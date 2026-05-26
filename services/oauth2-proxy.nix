{ config, pkgs, ... }:
{
  sops.secrets."oauth2-proxy/client_secret" = {
    group = "oauth2-proxy";
    owner = "oauth2-proxy";
  };
  sops.secrets."oauth2-proxy/cookie_secret" = {
    group = "oauth2-proxy";
    owner = "oauth2-proxy";

  };

  # https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc
  services.oauth2-proxy = {
    enable = true;
    provider = "oidc";
    clientID = "oauth2-proxy";
    clientSecretFile = "${config.sops.secrets."oauth2-proxy/client_secret".path}";

    cookie = {
      domain = ".alexmayers.co.za"; # Enables SSO across subdomains
      secretFile = "${config.sops.secrets."oauth2-proxy/cookie_secret".path}";
      secure = true;
    };

    extraConfig = {
      oidc-issuer-url = "https://identity.alexmayers.co.za/realms/master";
      code-challenge-method = "S256";
      pass-authorization-header = "true";
      set-authorization-header = "true";
      email-domain = "*";

      whitelist-domain = ".alexmayers.co.za";

      session-store-type = "redis";
      redis-connection-url = "redis://127.0.0.1:6379";

      standard-logging-format = ''{"timestamp":"{{.Timestamp}}","file":"{{.File}}","msg":"{{.Message}}"}'';
      auth-logging-format = ''{"client":"{{.Client}}","request_id":"{{.RequestID}}","user":"{{.Username}}","timestamp":"{{.Timestamp}}","status":"{{.Status}}","msg":"{{.Message}}"}'';
      request-logging-format = ''{"client":"{{.Client}}","request_id":"{{.RequestID}}","user":"{{.Username}}","timestamp":"{{.Timestamp}}","host":"{{.Host}}","method":"{{.RequestMethod}}","upstream":"{{.Upstream}}","uri":"{{.RequestURI}}","proto":"{{.Protocol}}","agent":"{{.UserAgent}}","status":{{.StatusCode}},"size":{{.ResponseSize}},"duration":"{{.RequestDuration}}"}'';
    };
  };
  services.redis.servers.oauth2-proxy = {
    enable = true;
    port = 6379;
  };
}
