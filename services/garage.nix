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
        # LMDB is upstream's default since 0.9.0 and the only engine here that
        # survives concurrent PutObject. sqlite serializes writers and a
        # parallel `attic push` queued enough fsync work to stall every reader
        # and took Loki, Mimir, and Attic down with it
        # (docs/adr/2026-09-05-garage-lmdb-migration.md). The one-time
        # conversion runs in garage-convert-sqlite-to-lmdb.service below.
        # lmdb_map_size is left unset: upstream defaults to 1 TiB on 64-bit,
        # which is the max the db may reach, not an allocation.
        db_engine = "lmdb";
        # Sync on commit. Costs write throughput, buys us not losing the
        # only metadata copy when the hypervisor drops.
        metadata_fsync = true;
        # Single node on proxmox-observability. RF=2 on one hypervisor was
        # two copies on the same TrueNAS mirror and turned a VM reboot into a
        # write outage (docs/adr/2026-09-07-garage-on-obs-1.md).
        replication_factor = 1;

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
        # Garage's own snapshots are the only consistent copy of the metadata
        # db; a filesystem-level copy taken while Garage runs may be torn.
        # Garage keeps the two most recent and deletes the rest.
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
          # chown meta to garage — that makes the db readonly in the service.
          serviceConfig.SupplementaryGroups = [ "keys" ];
        }
        // lib.optionalAttrs cfg.mountNfs {
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
        };

        # One-time sqlite -> LMDB conversion, idempotent after that.
        #
        # Runs as root on purpose: /var/lib/garage is idmapped, so on disk the
        # tree is nobody:nogroup and the garage unit's StateDirectory maps that
        # uid to `garage`. Converting as User=garage fails with Permission
        # denied on the output db, so convert as root and copy the on-disk
        # ownership onto the result. Do not chown the tree to `garage`.
        #
        # garage.service Requires this unit, so a failed conversion leaves
        # Garage down instead of starting it on an empty LMDB. Recovery is
        # docs/runbooks/garage-lmdb.md.
        garage-convert-sqlite-to-lmdb = {
          description = "Convert Garage metadata from sqlite to LMDB";
          before = [ "garage.service" ];
          requiredBy = [ "garage.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ config.services.garage.package ];
          script = ''
            set -euo pipefail

            meta=/var/lib/garage/meta
            sqlite="$meta/db.sqlite"
            lmdb="$meta/db.lmdb"
            staging="$meta/db.lmdb.converting"

            # Keep the retired sqlite db, but under a name Garage will not
            # open: two engines in one metadata_dir is ambiguous.
            retire_sqlite() {
              local ts f
              ts=$(date -u +%Y%m%dT%H%M%SZ)
              for f in "$sqlite" "$sqlite-wal" "$sqlite-shm"; do
                if [ -e "$f" ]; then
                  mv -v "$f" "$f.migrated-$ts"
                fi
              done
            }

            if [ -e "$lmdb/data.mdb" ]; then
              echo "LMDB already present at $lmdb; nothing to convert."
              retire_sqlite
              exit 0
            fi

            if [ ! -e "$sqlite" ]; then
              echo "Neither $lmdb nor $sqlite exists; Garage will create LMDB."
              exit 0
            fi

            # Ordering only guarantees we start before garage.service starts,
            # not that its stop job finished. Converting a db Garage still has
            # open would silently drop every write it makes afterwards, so
            # check rather than assume.
            waited=0
            while systemctl is-active --quiet garage.service && [ "$waited" -lt 60 ]; do
              sleep 1
              waited=$((waited + 1))
            done
            if systemctl is-active --quiet garage.service; then
              echo "ERROR: garage.service is still running; refusing to convert a live db." >&2
              exit 1
            fi

            # convert-db writes a second full copy and we keep the original.
            need=$(stat -c %s "$sqlite")
            avail=$(df --output=avail -B1 "$meta" | tail -1)
            if [ "$avail" -lt "$((need * 2))" ]; then
              echo "ERROR: $meta has $avail bytes free; converting a $need byte db needs $((need * 2))." >&2
              exit 1
            fi

            if [ -e "$sqlite-wal" ]; then
              echo "NOTE: $sqlite-wal exists (unclean shutdown); convert-db replays it on open."
            fi

            rm -rf "$staging"
            echo "Converting $sqlite to LMDB; takes a few minutes on a 400 MiB db."
            garage convert-db -a sqlite -i "$sqlite" -b lmdb -o "$staging"

            if [ ! -s "$staging/data.mdb" ]; then
              echo "ERROR: convert-db exited 0 but $staging/data.mdb is missing or empty." >&2
              rm -rf "$staging"
              exit 1
            fi

            chown -R --reference="$sqlite" "$staging"
            # Publish before retiring sqlite. Interrupted here, the next start
            # finds db.lmdb and retires sqlite then; the reverse order could
            # leave neither and Garage would create an empty db.
            mv "$staging" "$lmdb"
            retire_sqlite
            echo "Converted to $lmdb. Retired sqlite kept as $sqlite.migrated-*; remove it once the cluster is verified."
          '';
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
            Restart = "on-failure";
            RestartSec = "15s";
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
            for _ in {1..60}; do
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
