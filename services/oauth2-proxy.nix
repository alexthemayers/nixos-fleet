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
    #    redirectURL = "http://127.0.0.1/oauth2/callback";

    # Use sops-nix or agenix for these secrets in production
    #    keyFile = config.sops.secrets."".path;

    cookie = {
      domain = ".alexmayers.co.za"; # Enables SSO across subdomains
      secretFile = "${config.sops.secrets."oauth2-proxy/cookie_secret".path}";
      secure = true;
    };

    extraConfig = {
      oidc-issuer-url = "https://identity.alexmayers.co.za/realms/master";
      code-challenge-method = "S256";
      # Optional: Pass the OIDC token upstream to your backend
      pass-authorization-header = "true";
      set-authorization-header = "true";
      email-domain = "*";

      whitelist-domain = ".alexmayers.co.za";

      # Allow users to bypass auth for specific paths if needed
      # skip_auth_routes = "^/public/.*";
      session-store-type = "redis";
      redis-connection-url = "redis://127.0.0.1:6379";
    };
  };
  services.redis.servers.oauth2-proxy = {
    enable = true;
    port = 6379;
  };
}
