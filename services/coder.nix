{
  config,
  pkgs,
  lib,
  ...
}:

let
  coder-version = "2.33.8";

  coder-src = pkgs.fetchurl {
    url = "https://github.com/coder/coder/releases/download/v${coder-version}/coder_${coder-version}_linux_amd64.tar.gz";
    hash = "sha256-wqMmIQtzMP8wKCzztJ7lO8nDesZF5x4epHDyM1DBG1A=";
  };

  coder-pkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "coder";
    version = coder-version;
    src = coder-src;
    nativeBuildInputs = [
      pkgs.installShellFiles
      pkgs.makeBinaryWrapper
    ];

    unpackPhase = "tar -xzf $src";

    installPhase = ''
      mkdir -p $out/bin
      install -m755 coder $out/bin/coder
      wrapProgram $out/bin/coder --prefix PATH : ${lib.makeBinPath [ pkgs.terraform ]}
    '';
  };
in
{
  sops.secrets."postgres/coder_password" = {
    owner = "coder";
  };

  sops.secrets."coder/client_secret" = {
    owner = "coder";
  };

  sops.templates."coder-env" = {
    owner = "coder";
    content = ''
      CODER_PG_CONNECTION_URL="postgres://coder:${
        config.sops.placeholder."postgres/coder_password"
      }@xcloud-postgres:5432/coder?sslmode=disable"
      CODER_OIDC_CLIENT_SECRET="${config.sops.placeholder."coder/client_secret"}"
      CODER_OIDC_SIGN_IN_TEXT="Sign in with Keycloak"
    '';
  };

  users.users.coder = {
    group = "coder";
    isSystemUser = true;
    home = "/var/lib/coder";
    createHome = true;
    extraGroups = [
      "docker"
      "podman"
    ];
  };

  users.groups.coder = { };

  systemd.services.coder = {
    description = "Coder Server";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = [
      pkgs.terraform
      pkgs.git
      pkgs.bash
    ];

    serviceConfig = {
      ExecStart = "${coder-pkg}/bin/coder server";
      EnvironmentFile = [ config.sops.templates."coder-env".path ];
      Environment = [
        "CODER_HTTP_ADDRESS=0.0.0.0:7080"
        "CODER_ACCESS_URL=https://coder.alexmayers.co.za"
        "CODER_OIDC_ISSUER_URL=https://identity.alexmayers.co.za/realms/master"
        "CODER_OIDC_CLIENT_ID=coder"
        "CODER_OIDC_EMAIL_DOMAIN="
        "CODER_OIDC_ALLOW_SIGNUPS=false"
        "CODER_OIDC_EMAIL_FIELD=email"
        "CODER_DISABLE_PASSWORD_AUTH=true"
        "CODER_OIDC_SCOPES=openid,profile,email,offline_access"
        ''CODER_OIDC_AUTH_URL_PARAMS='{"access_type":"offline"}''
        "CODER_SESSION_DURATION=10h"
        "CODER_LOG_FORMAT=json"
        "CODER_PROMETHEUS_ENABLE=true"
        "CODER_PROMETHEUS_ADDRESS=0.0.0.0:2112"
      ];
      User = "coder";
      Group = "coder";
      Restart = "always";
      RestartSec = "5s";
      StateDirectory = "coder";
      WorkingDirectory = "/var/lib/coder";
    };
  };
}
