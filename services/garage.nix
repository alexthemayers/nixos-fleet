{
  config,
  pkgs,
  lib,
  ...
}:

let
  hostname = config.networking.hostName;
  isProxmoxDb = hostname == "proxmox-db";
  isRpi4 = hostname == "rpi4";
in
{
  # Only evaluate and configure if we are on one of the target S3 hosts
  config = lib.mkIf (isProxmoxDb || isRpi4) {

    sops.secrets."garage/rpc_secret" = {
      owner = "root";
      group = "keys";
      mode = "0440";
    };

    sops.secrets."garage/admin_token" = {
      owner = "root";
      group = "keys";
      mode = "0440";
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
        db_engine = "sqlite";
        replication_factor = 2; # Replicated across proxmox-db and rpi4

        rpc_bind_addr = "[::]:3901";
        rpc_public_addr = "${hostname}:3901";

        s3_api = {
          s3_region = "garage";
          api_bind_addr = "[::]:3902";
          root_domain = ".s3.alexmayers.co.za";
        };

        admin = {
          api_bind_addr = "[::]:3903";
        };

        metadata_dir = "/var/lib/garage/meta";
        data_dir = if isProxmoxDb then "/mnt/nfs/garage/data" else "/var/lib/garage/data";
      };
    };

    # NFS Mount & wait service (Only on proxmox-db)
    fileSystems = lib.mkIf isProxmoxDb {
      "/mnt/nfs/garage/data" = {
        device = "truenas-scale:/mnt/ssd/garage/data";
        fsType = "nfs";
        options = [
          "rw"
          "nfsvers=4.2"
          "_netdev"
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "x-systemd.requires=wait-for-host-garage.service"
          "x-systemd.after=wait-for-host-garage.service"
        ];
      };
    };

    # Firewall port rules allowed globally on the trusted Tailscale interface
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
          serviceConfig.SupplementaryGroups = [ "keys" ];
        };
      }
      (lib.mkIf isProxmoxDb {
        # Proxmox-DB specific services

        garage = {
          unitConfig.RequiresMountsFor = [ "/mnt/nfs/garage/data" ];
        };

        # Bootstrap S3 (Only on proxmox-db)
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
            # Wait for the Garage daemon S3 API to be responsive
            for i in {1..30}; do
              if garage status >/dev/null 2>&1; then
                echo "Garage daemon is online!"
                break
              fi
              echo "Waiting for Garage daemon..."
              sleep 2
            done

            # Create key directory if not present
            mkdir -p /var/lib/garage/keys

            bootstrap_s3() {
              local name=$1
              local key_file="/var/lib/garage/keys/$name-key.txt"

              # Check if the key already exists
              if ! garage key info "$name-key" >/dev/null 2>&1; then
                echo "Creating S3 key for $name..."
                if output=$(garage key create "$name-key" 2>/dev/null); then
                  echo "$output" > "$key_file"
                  chmod 600 "$key_file"
                  echo "Saved key details to $key_file"
                else
                  echo "Warning: Failed to create S3 key $name-key. The cluster might not have quorum or layout applied yet."
                  return 0
                fi
              else
                echo "S3 key for $name already exists."
              fi

              # Check if the bucket already exists
              if ! garage bucket info "$name" >/dev/null 2>&1; then
                echo "Creating S3 bucket $name..."
                if ! garage bucket create "$name" 2>/dev/null; then
                  echo "Warning: Failed to create S3 bucket $name."
                  return 0
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
          '';
        };
      })
    ];

    fleet.waitForHost = lib.mkIf isProxmoxDb {
      garage.host = "truenas-scale";
    };
  };
}
