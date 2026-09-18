{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.fleet.services.garage;
  hostname = config.networking.hostName;
  iscsiDevice = "/dev/disk/by-path/ip-${cfg.iscsiPortal}:3260-iscsi-${cfg.iscsiTarget}-lun-${toString cfg.iscsiLun}";
  metaDir = if cfg.mountIscsi then "${cfg.iscsiMount}/meta" else "/var/lib/garage/meta";
  resolvedDataDir =
    if cfg.mountIscsi then
      "${cfg.iscsiMount}/data"
    else if cfg.mountNfs then
      cfg.loopbackMount
    else
      cfg.dataDir;
  iscsiMountUnit = "${escapeSystemdPath cfg.iscsiMount}.mount";
  loopMountUnit = "${escapeSystemdPath cfg.loopbackMount}.mount";
  escapeSystemdPath =
    path:
    let
      inherit (lib)
        hasPrefix
        hasSuffix
        removePrefix
        removeSuffix
        replaceStrings
        ;
      p1 = if hasPrefix "/" path then removePrefix "/" path else path;
      p2 = if hasSuffix "/" p1 then removeSuffix "/" p1 else p1;
      p3 = replaceStrings [ "-" ] [ "\\x2d" ] p2;
    in
    replaceStrings [ "/" ] [ "-" ] p3;
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
      description = ''
        Mount the leftover TrueNAS NFS share (and the loopback ext4 image).
        Not Garage data_dir when mountIscsi is set; keep it only so migrate
        can copy blocks off `.blocks-ext4`.
      '';
    };

    nfsShare = lib.mkOption {
      type = lib.types.str;
      default = "truenas-scale:/mnt/ssd/garage/data";
      description = "The NFS share path to mount from TrueNAS.";
    };

    mountIscsi = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Log into the TrueNAS iSCSI LUN and use it for Garage data_dir and
        metadata_dir. Portal must be the LAN address, not MagicDNS
        (docs/adr/2026-09-18-garage-iscsi.md).
      '';
    };

    iscsiPortal = lib.mkOption {
      type = lib.types.str;
      default = "192.168.3.9";
      description = "TrueNAS enp6s16 LAN IPv4. Do not use the Tailscale name.";
    };

    iscsiTarget = lib.mkOption {
      type = lib.types.str;
      default = "iqn.2005-10.org.freenas.ctl:garage";
      description = "iSCSI target IQN on TrueNAS.";
    };

    iscsiLun = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      description = "LUN id on the Garage target.";
    };

    iscsiMount = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/iscsi/garage";
      description = "ext4 mount of the Garage iSCSI LUN. data/ and meta/ live under it.";
    };

    iscsiInitiatorName = lib.mkOption {
      type = lib.types.str;
      default = "iqn.2026-09.za.co.alexmayers:proxmox-observability";
      description = "Open-iSCSI initiator IQN; must match the TrueNAS initiator ACL.";
    };

    bootstrapS3 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to bootstrap S3 buckets and keys on this node.";
    };

    # Raw NFS PutObject is open/write/close/rename per ~256 KiB Attic chunk.
    # Loopback ext4 on a sparse image on that share is the same pattern as
    # services.build-cache (docs/adr/2026-09-18-garage-blocks-loopback-ext4.md).
    loopbackImage = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nfs/garage/data/.garage-blocks.img";
      description = "Sparse ext4 image on the NFS share that holds Garage blocks.";
    };

    loopbackMount = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nfs/garage/data/.blocks-ext4";
      description = "Where the Garage block image is loop-mounted. This is data_dir.";
    };

    loopbackImageSize = lib.mkOption {
      type = lib.types.str;
      default = "100G";
      description = "Virtual size of the sparse block image. Init will only grow, never shrink.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.fleet.appOnThisHost.garage {
      fleet.services.garage = {
        enable = true;
        dataDir = "/mnt/nfs/garage/data";
        # NFS stays mounted so garage-iscsi-migrate can copy `.blocks-ext4`
        # and LMDB. Garage itself RequiresMountsFor the iSCSI fs only.
        # Set mountNfs = false after /health 200 on the LUN.
        mountNfs = true;
        mountIscsi = true;
        nfsShare = "truenas-scale:/mnt/ssd/garage/data";
        bootstrapS3 = true;
      };
    })
    (lib.mkIf cfg.enable {
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

          metadata_dir = metaDir;
          # Garage's own snapshots are the only consistent copy of the metadata
          # db; a filesystem-level copy taken while Garage runs may be torn.
          # Garage keeps the two most recent and deletes the rest.
          metadata_auto_snapshot_interval = "6h";
          data_dir = resolvedDataDir;
        };
      };

      # NFS mount. Shared helper already sets nconnect=8 and noatime.
      # Kept as the migrate source while mountIscsi is also on.
      fileSystems = lib.mkMerge [
        (lib.mkIf cfg.mountNfs {
          ${cfg.dataDir} = {
            device = cfg.nfsShare;
            fsType = "nfs";
            options = import ../config/nfs-mount.nix "garage" [ ];
          };
          ${cfg.loopbackMount} = {
            device = cfg.loopbackImage;
            fsType = "ext4";
            options = [
              "loop"
              "noatime"
              "nofail"
              "x-systemd.requires=garage-loop-img-init.service"
              "x-systemd.after=garage-loop-img-init.service"
            ];
          };
        })
        (lib.mkIf cfg.mountIscsi {
          ${cfg.iscsiMount} = {
            device = iscsiDevice;
            fsType = "ext4";
            options = [
              "noatime"
              "_netdev"
              "x-systemd.requires=wait-for-host-garage-iscsi.service"
              "x-systemd.after=wait-for-host-garage-iscsi.service"
              "x-systemd.requires=iscsi-login-garage.service"
              "x-systemd.after=iscsi-login-garage.service"
              "x-systemd.requires=garage-iscsi-mkfs.service"
              "x-systemd.after=garage-iscsi-mkfs.service"
              "x-systemd.device-timeout=120"
            ];
          };
        })
      ];

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
        (
          {
            # Common systemd service configs for garage
            garage = {
              unitConfig.RequiresMountsFor =
                if cfg.mountIscsi then
                  [ cfg.iscsiMount ]
                else if cfg.mountNfs then
                  [
                    cfg.dataDir
                    cfg.loopbackMount
                  ]
                else
                  [ cfg.dataDir ];
              serviceConfig.DynamicUser = lib.mkForce false;
              serviceConfig.User = "garage";
              serviceConfig.Group = "garage";
              # StateDirectory ID-maps /var/lib/garage: on disk the tree is
              # nobody:nogroup; inside the unit that uid is this user. Do not
              # chown meta to garage — that makes the db readonly in the service.
              serviceConfig.SupplementaryGroups = [ "keys" ];
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
              after = lib.optionals cfg.mountIscsi [
                iscsiMountUnit
                "garage-iscsi-migrate.service"
              ];
              requires = lib.optionals cfg.mountIscsi [ iscsiMountUnit ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              path = [ config.services.garage.package ];
              script = ''
                set -euo pipefail

                meta=${metaDir}
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
          // lib.optionalAttrs cfg.mountNfs {
            garage-loop-img-init = {
              description = "Initialize Garage block loopback image on NFS";
              after = [ "${escapeSystemdPath cfg.dataDir}.mount" ];
              requires = [ "${escapeSystemdPath cfg.dataDir}.mount" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              path = [
                pkgs.coreutils
                pkgs.e2fsprogs
                pkgs.util-linux
              ];
              script = ''
                set -euo pipefail
                IMG="${cfg.loopbackImage}"
                if findmnt --source "$IMG" >/dev/null 2>&1 \
                  || findmnt ${cfg.loopbackMount} >/dev/null 2>&1; then
                  echo "Loop image is mounted; skipping fsck/grow."
                  exit 0
                fi
                if [ ! -f "$IMG" ]; then
                    echo "Creating ${cfg.loopbackImageSize} sparse Garage block image..."
                    truncate -s ${cfg.loopbackImageSize} "$IMG"
                    ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F -L garage-blocks "$IMG"
                  else
                    current=$(${pkgs.coreutils}/bin/stat -c %s "$IMG")
                    desired=$(${pkgs.coreutils}/bin/numfmt --from=iec ${cfg.loopbackImageSize})
                    if [ "$desired" -lt "$current" ]; then
                      echo "Refusing to shrink $IMG from $current to $desired bytes." >&2
                      exit 1
                    fi
                    rc=0
                    ${pkgs.e2fsprogs}/bin/e2fsck -fp "$IMG" || rc=$?
                    if [ "$rc" -gt 1 ]; then
                      echo "e2fsck reported uncorrected errors (exit $rc) on $IMG" >&2
                      exit 1
                    fi
                    if [ "$desired" -gt "$current" ]; then
                      echo "Growing $IMG from $current to $desired bytes..."
                      truncate -s ${cfg.loopbackImageSize} "$IMG"
                      ${pkgs.e2fsprogs}/bin/resize2fs "$IMG"
                    fi
                  fi
              '';
            };
            garage-loop-permissions = {
              description = "Garage loopback block dir ownership";
              wantedBy = [ "multi-user.target" ];
              before = lib.optionals (!cfg.mountIscsi) [ "garage.service" ];
              after = [ loopMountUnit ];
              requires = [ loopMountUnit ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              # Ext4 mountpoint only. Never chown /var/lib/garage (idmapped meta).
              script = ''
                chown garage:garage ${cfg.loopbackMount}
                chmod 0750 ${cfg.loopbackMount}
              '';
            };
          }
        )
        (lib.mkIf cfg.mountIscsi {
          iscsi-login-garage = {
            description = "Login to TrueNAS iSCSI target for Garage";
            after = [
              "network-online.target"
              "iscsid.service"
              "wait-for-host-garage-iscsi.service"
            ];
            wants = [
              "network-online.target"
              "iscsid.service"
            ];
            requires = [ "wait-for-host-garage-iscsi.service" ];
            before = [ iscsiMountUnit ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStop = "${pkgs.openiscsi}/bin/iscsiadm -m node -T ${cfg.iscsiTarget} -p ${cfg.iscsiPortal} --logout";
            };
            path = [ pkgs.openiscsi ];
            script = ''
              set -euo pipefail
              ${pkgs.openiscsi}/bin/iscsiadm -m discovery -t sendtargets -p ${cfg.iscsiPortal}
              ${pkgs.openiscsi}/bin/iscsiadm -m node -T ${cfg.iscsiTarget} -p ${cfg.iscsiPortal} \
                --op update -n node.startup -v automatic
              set +e
              ${pkgs.openiscsi}/bin/iscsiadm -m node -T ${cfg.iscsiTarget} -p ${cfg.iscsiPortal} --login
              rc=$?
              set -e
              # 15: session already exists
              if [ "$rc" -ne 0 ] && [ "$rc" -ne 15 ]; then
                exit "$rc"
              fi
            '';
          };
          garage-iscsi-mkfs = {
            description = "Create ext4 on the Garage iSCSI LUN if empty";
            after = [ "iscsi-login-garage.service" ];
            requires = [ "iscsi-login-garage.service" ];
            before = [ iscsiMountUnit ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [
              pkgs.coreutils
              pkgs.e2fsprogs
              pkgs.util-linux
            ];
            script = ''
              set -euo pipefail
              DEV="${iscsiDevice}"
              deadline=$((SECONDS + 60))
              while [ ! -e "$DEV" ]; do
                if [ "$SECONDS" -ge "$deadline" ]; then
                  echo "ERROR: $DEV did not appear after iSCSI login." >&2
                  exit 1
                fi
                sleep 1
              done
              if findmnt ${cfg.iscsiMount} >/dev/null 2>&1; then
                echo "Garage iSCSI fs is mounted; skipping fsck/mkfs."
                exit 0
              fi
              fstype=$(blkid -o value -s TYPE "$DEV" || true)
              if [ -z "$fstype" ]; then
                echo "Formatting $DEV as ext4 (label garage)."
                mkfs.ext4 -F -L garage "$DEV"
                exit 0
              fi
              rc=0
              e2fsck -fp "$DEV" || rc=$?
              if [ "$rc" -gt 1 ]; then
                echo "e2fsck reported uncorrected errors (exit $rc) on $DEV" >&2
                exit 1
              fi
            '';
          };
          garage-iscsi-migrate = {
            description = "Copy Garage LMDB and blocks onto the iSCSI filesystem";
            wantedBy = [ "garage.service" ];
            before = [ "garage.service" ];
            after = [ iscsiMountUnit ] ++ lib.optionals cfg.mountNfs [ loopMountUnit ];
            requires = [ iscsiMountUnit ];
            wants = lib.optionals cfg.mountNfs [ loopMountUnit ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [
              pkgs.coreutils
            ];
            # Dest is real ext4: chown garage:garage is required.
            # Never chown /var/lib/garage (idmapped leftover).
            script = ''
              set -euo pipefail
              waited=0
              while systemctl is-active --quiet garage.service && [ "$waited" -lt 60 ]; do
                sleep 1
                waited=$((waited + 1))
              done
              if systemctl is-active --quiet garage.service; then
                echo "ERROR: garage.service is still running; refusing to copy a live db." >&2
                exit 1
              fi

              meta_src=/var/lib/garage/meta
              meta_dst=${cfg.iscsiMount}/meta
              data_src=${cfg.loopbackMount}
              data_dst=${cfg.iscsiMount}/data
              mkdir -p "$meta_dst" "$data_dst"

              if [ -e "$meta_src/db.lmdb/data.mdb" ] && [ ! -e "$meta_dst/db.lmdb/data.mdb" ]; then
                echo "Copying LMDB from $meta_src to $meta_dst"
                cp -a "$meta_src/." "$meta_dst/"
              else
                echo "LMDB already on iSCSI or source missing; skipping meta copy."
              fi

              if [ -d "$data_src" ] && [ -z "$(ls -A "$data_dst" 2>/dev/null || true)" ]; then
                echo "Copying blocks from $data_src to $data_dst"
                cp -a "$data_src/." "$data_dst/"
              else
                echo "Block dir already populated or NFS loop not mounted; skipping data copy."
              fi

              chown -R garage:garage ${cfg.iscsiMount}
              chmod 0750 ${cfg.iscsiMount} "$meta_dst" "$data_dst"
            '';
          };
        })
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

      boot.kernelModules = lib.mkIf cfg.mountIscsi [ "iscsi_tcp" ];
      environment.systemPackages = lib.mkIf cfg.mountIscsi [ pkgs.openiscsi ];
      services.openiscsi = lib.mkIf cfg.mountIscsi {
        enable = true;
        name = cfg.iscsiInitiatorName;
      };

      fleet.waitForHost = lib.mkMerge [
        (lib.mkIf cfg.mountNfs {
          garage.host = "truenas-scale";
        })
        (lib.mkIf cfg.mountIscsi {
          garage-iscsi = {
            host = cfg.iscsiPortal;
            port = 3260;
          };
        })
      ];

      assertions = [
        {
          assertion = !(lib.hasPrefix "100." cfg.iscsiPortal);
          message = ''
            fleet.services.garage.iscsiPortal is ${cfg.iscsiPortal}.
            That looks like a Tailscale IP. iSCSI must use the TrueNAS LAN
            address (192.168.3.9) so PutObject stays on the 10 Gbit VF, not
            MagicDNS MTU 1280 (docs/adr/2026-09-18-garage-iscsi.md).
          '';
        }
      ];
    })
  ];
}
