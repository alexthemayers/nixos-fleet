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
    reverseProxy = true;
    trustedProxyIP = [
      "127.0.0.1"
      "::1"
    ];
    redirectURL = "https://auth.alexmayers.co.za/oauth2/callback";

    cookie = {
      domain = ".alexmayers.co.za"; # Enables SSO across subdomains
      secretFile = "${config.sops.secrets."oauth2-proxy/cookie_secret".path}";
      secure = true;
      refresh = "15s";
      expire = "10h"; # Absolute session lifetime matching Keycloak
    };

    extraConfig = {
      oidc-issuer-url = "https://identity.alexmayers.co.za/realms/master";
      code-challenge-method = "S256";
      pass-authorization-header = "true";
      pass-access-token = true;
      set-authorization-header = "true";
      email-domain = "*";

      skip-jwt-bearer-tokens = true;
      extra-jwt-issuers = "https://identity.alexmayers.co.za/realms/master=grafana";

      whitelist-domain = ".alexmayers.co.za";

      backend-logout-url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/logout?client_id=oauth2-proxy&post_logout_redirect_uri=https://auth.alexmayers.co.za/oauth2/sign_in";

      session-store-type = "redis";
      redis-connection-url = "redis://xcloud-postgres:6379";

      metrics-address = "0.0.0.0:44180";

      standard-logging-format = ''{"timestamp":"{{.Timestamp}}","file":"{{.File}}","msg":"{{.Message}}"}'';
      auth-logging-format = ''{"client":"{{.Client}}","request_id":"{{.RequestID}}","user":"{{.Username}}","timestamp":"{{.Timestamp}}","status":"{{.Status}}","msg":"{{.Message}}"}'';
      request-logging-format = ''{"client":"{{.Client}}","request_id":"{{.RequestID}}","user":"{{.Username}}","timestamp":"{{.Timestamp}}","host":"{{.Host}}","method":"{{.RequestMethod}}","upstream":"{{.Upstream}}","uri":"{{.RequestURI}}","proto":"{{.Protocol}}","agent":"{{.UserAgent}}","status":{{.StatusCode}},"size":{{.ResponseSize}},"duration":"{{.RequestDuration}}"}'';
    };
  };
}
