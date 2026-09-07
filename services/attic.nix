{
  config,
  pkgs,
  lib,
  ...
}:
let
  atticNarProxy = pkgs.buildGoModule {
    pname = "attic-nar-proxy";
    version = "1.0.0";
    src = ./attic-nar-proxy;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    meta.mainProgram = "attic-nar-proxy";
  };
in
{
  options.fleet.services.attic.mode = lib.mkOption {
    type = lib.types.enum [
      "monolithic"
      "api-server"
    ];
    default = "api-server";
    description = ''
      Which atticd role this host runs. Exactly one host in the fleet may be
      "monolithic"; it runs the garbage collector and other background jobs.
      Sets services.atticd.mode so renaming the host cannot silently drop GC.
    '';
  };

  config = {
    # atticd talks to Postgres through PgBouncer on :5432. Raw :5433 is
    # firewalled on xcloud-postgres. ATTIC_SERVER_DATABASE_URL in attic/env
    # must use xcloud-postgres:5432, not :5433.
    fleet.waitFor.postgres.attic.forServices = [ "atticd.service" ];
    fleet.waitFor.garage.attic.forServices = [ "atticd.service" ];

    sops.secrets."attic/env" = {
      owner = config.services.atticd.user;
      group = config.services.atticd.group;
      mode = "0440";
      restartUnits = [ "atticd.service" ];
    };

    users.users.atticd = {
      group = "atticd";
      isSystemUser = true;
    };
    users.groups.atticd = { };

    services.atticd = {
      user = config.users.users.atticd.name;
      group = config.users.groups.atticd.name;
      enable = true;
      environmentFile = config.sops.secrets."attic/env".path;
      mode = config.fleet.services.attic.mode;
      # Empty [database]: URL comes from ATTIC_SERVER_DATABASE_URL in attic/env.
      # The module's mkDefault sqlite would otherwise win.
      settings = {
        listen = "127.0.0.1:8081";
        database = lib.mkForce { };
        chunking = {
          avg-size = 262144;
          max-size = 1048576;
          min-size = 16384;
          nar-size-threshold = 65536;
        };
        storage = {
          bucket = "attic";
          endpoint = "http://proxmox-observability:3902";
          region = "garage";
          type = "s3";
        };
      };
    };

    # atticd 307s single-chunk NARs to a Garage presigned URL. Nix treats a
    # 307 with an empty body as "path is not valid" and will not substitute.
    # Caddy cannot follow that hop: `{rp.header.Location}` is parsed as
    # host:port (502), and rewrite/map percent-encodes the query (SigV4 400).
    # This proxy GETs the Location URL as-is and returns 200 to Nix.
    systemd.services.attic-nar-proxy = {
      description = "Follow atticd S3 redirects so Nix can substitute";
      after = [ "atticd.service" ];
      requires = [ "atticd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${atticNarProxy}/bin/attic-nar-proxy -listen :8080 -upstream http://127.0.0.1:8081";
        DynamicUser = true;
        Restart = "always";
        RestartSec = "2s";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 ];
  };
}
