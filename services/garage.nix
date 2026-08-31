{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.fleet.services.garage;
  hostname = config.networking.hostName;
in
{
  options.fleet.services.garage = {
    enable = lib.mkEnableOption "Garage S3 storage cluster";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/garage/data";
      description = "Directory where Garage will store its data blocks.";
    };

    mountNfs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to mount the Garage data directory via TrueNAS NFS.";
    };

    nfsShare = lib.mkOption {
      type = lib.types.str;
      default = "truenas-scale:/mnt/ssd/garage/data";
      description = "The NFS share path to mount from TrueNAS.";
    };

    bootstrapS3 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to bootstrap S3 buckets and keys on this node.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Both secrets reach Garage as *file paths* in the unit's environment, so the
    # unit definition is identical before and after a rotation and nothing would
    # otherwise restart it. Without restartUnits, `sops set` + deploy writes the
    # new secret to disk while Garage keeps serving with the old one held in
    # memory -- the rotation looks applied but is not.
    sops.secrets."garage/rpc_secret" = {
      owner = "root";
      group = "keys";
      mode = "0440";
      restartUnits = [ "garage.service" ];
    };

    sops.secrets."garage/admin_token" = {
      owner = "root";
      group = "keys";
      mode = "0440";
      restartUnits = [ "garage.service" ];
    };

    services.garage = {
      enable = true;
      package = pkgs.garage;

      # Inject the RPC secret and admin token paths directly as environment variables
      extraEnvironment = {
        GARAGE_RPC_SECRET_FILE = config.sops.secrets."garage/rpc_secret".path;
        GARAGE_ADMIN_TOKEN_FILE = config.sops.secrets."garage/admin_token".path;
        GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";
      };

      settings = {
        # Stay on sqlite: convert-db to LMDB failed on this cluster
        # (Permission denied under the garage idmap, then
        # "Invalid column type Integer at index: 1, name: v").
        # metadata_fsync turns PRAGMA synchronous=OFF into NORMAL so a
        # PutObject burst does not tear db.sqlite. Parallel attic push
        # still uses ATTIC_PUSH_JOBS; keep it modest until LMDB works.
        db_engine = "sqlite";
        metadata_fsync = true;
        # Live layout is db-1 (dc1) + db-2 (dc2) only. A third zone (the Pi)
        # made writes require all three when zone redundancy was `maximum`.
        replication_factor = 2;

        rpc_bind_addr = "0.0.0.0:3901";
        rpc_public_addr = "${hostname}.bee-phrygian.ts.net:3901";

        s3_api = {
          s3_region = "garage";
          api_bind_addr = "0.0.0.0:3902";
          root_domain = ".s3.alexmayers.co.za";
        };

        admin = {
          api_bind_addr = "0.0.0.0:3903";
        };

        metadata_dir = "/var/lib/garage/meta";
        # Snapshot sqlite so a torn write does not take the whole cluster with
        # it. Do not copy db.sqlite while Garage is running.
        metadata_auto_snapshot_interval = "6h";
        data_dir = cfg.dataDir;
      };
    };

    # NFS Mount & wait service
    fileSystems = lib.mkIf cfg.mountNfs {
      ${cfg.dataDir} = {
        device = cfg.nfsShare;
        fsType = "nfs";
        options = import ../config/nfs-mount.nix "garage" [ ];
      };
    };

    # Explicit on tailscale0 so these stay reachable after trustedInterfaces
    # was removed. Not a blanket trust of the interface.
    networking.firewall.interfaces."tailscale0" = {
      allowedTCPPorts = [
        3901
        3902
        3903
      ];
    };

    systemd.services = lib.mkMerge [
      {
        # Common systemd service configs for garage
        garage = {
          unitConfig.RequiresMountsFor = cfg.dataDir;
          serviceConfig.DynamicUser = lib.mkForce false;
          serviceConfig.User = "garage";
          serviceConfig.Group = "garage";
          # StateDirectory ID-maps /var/lib/garage: on disk the tree is
          # nobody:nogroup; inside the unit that uid is this user. Do not
          # chown meta to garage — that makes sqlite readonly in the service.
          serviceConfig.SupplementaryGroups = [ "keys" ];
        }
        // lib.optionalAttrs cfg.mountNfs {
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
        };
      }
      (lib.mkIf cfg.bootstrapS3 {
        # Bootstrap S3 specific service
        garage-bootstrap = {
          description = "Bootstrap Garage S3 Buckets and Keys";
          after = [ "garage.service" ];
          wants = [ "garage.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          environment = {
            GARAGE_RPC_SECRET_FILE = config.sops.secrets."garage/rpc_secret".path;
          };
          path = [
            config.services.garage.package
            pkgs.iputils
          ];
          script = ''
            set -euo pipefail

            # Wait for the Garage daemon S3 API to be responsive.
            # NOTE: this only proves the daemon answers. A cluster layout must
            # have been assigned and applied at least once, by hand, before key
            # and bucket creation can succeed:
            #   garage layout assign -z <zone> -c <capacity> <node-id>
            #   garage layout apply --version <n>
            # See docs/services/garage.md.
            online=0
            for _ in {1..30}; do
              if garage status >/dev/null 2>&1; then
                echo "Garage daemon is online!"
                online=1
                break
              fi
              echo "Waiting for Garage daemon..."
              sleep 2
            done

            if [ "$online" -ne 1 ]; then
              echo "Garage daemon did not become responsive; refusing to report success." >&2
              exit 1
            fi

            # Create key directory if not present
            mkdir -p /var/lib/garage/keys

            bootstrap_s3() {
              local name=$1
              local key_file="/var/lib/garage/keys/$name-key.txt"

              # Check if the key already exists
              if ! garage key info "$name-key" >/dev/null 2>&1; then
                echo "Creating S3 key for $name..."
                if output=$(garage key create "$name-key"); then
                  echo "$output" > "$key_file"
                  chmod 600 "$key_file"
                  echo "Saved key details to $key_file"
                else
                  echo "Failed to create S3 key $name-key. The cluster layout is probably not applied yet." >&2
                  return 1
                fi
              else
                echo "S3 key for $name already exists."
              fi

              # Check if the bucket already exists
              if ! garage bucket info "$name" >/dev/null 2>&1; then
                echo "Creating S3 bucket $name..."
                if ! garage bucket create "$name"; then
                  echo "Failed to create S3 bucket $name." >&2
                  return 1
                fi
              else
                echo "S3 bucket $name already exists."
              fi

              # Always ensure the key is linked to the bucket
              garage bucket allow "$name" --key "$name-key" --read --write
            }

            # Bootstrap our buckets and keys
            bootstrap_s3 "loki"
            bootstrap_s3 "mimir"
            bootstrap_s3 "web-assets"
            bootstrap_s3 "attic"
          '';
        };
      })
    ];

    users = {
      users.garage = {
        isSystemUser = true;
        group = "garage";
      };
      groups.garage = { };
    };
    fleet.waitForHost = lib.mkIf cfg.mountNfs {
      garage.host = "truenas-scale";
    };
  };
}
