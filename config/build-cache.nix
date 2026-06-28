{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.build-cache;

  escapeSystemdPath =
    path:
    let
      p1 = if hasPrefix "/" path then removePrefix "/" path else path;
      p2 = if hasSuffix "/" p1 then removeSuffix "/" p1 else p1;
      p3 = replaceStrings [ "-" ] [ "\\x2d" ] p2;
    in
    replaceStrings [ "/" ] [ "-" ] p3;

  attachmentSubmodule =
    { name, ... }:
    {
      options = {
        enable = mkEnableOption "NFS loopback build cache attachment";

        nfsDevice = mkOption {
          type = types.str;
          example = "truenas-scale:/mnt/ssd/buildcache";
          description = "The NFS share device path.";
        };

        nfsMountPoint = mkOption {
          type = types.str;
          default = "/mnt/nfs/${name}";
          description = "Where to mount the NFS share on the host.";
        };

        imageName = mkOption {
          type = types.str;
          default = "${name}.img";
          description = "Filename of the loopback image inside the NFS mount.";
        };

        imageSize = mkOption {
          type = types.str;
          default = "100G";
          description = "Size of the loopback image (e.g. 100G, 50G).";
        };

        targetMountPoint = mkOption {
          type = types.str;
          example = "/nix/var/nix/builds";
          description = "Where to mount the loopback image.";
        };

        owner = mkOption {
          type = types.str;
          default = "root";
          description = "Owner of the target directory.";
        };

        group = mkOption {
          type = types.str;
          default = "root";
          description = "Group of the target directory.";
        };

        mode = mkOption {
          type = types.str;
          default = "1775";
          description = "Permissions mode of the target directory.";
        };

        nixDaemonIntegration = mkOption {
          type = types.bool;
          default = false;
          description = "Configure nix-daemon to use the target mount as build compilation TMPDIR.";
        };
      };
    };

  activeAttachments = filterAttrs (name: att: att.enable) cfg.attachments;
  nixDaemonAttachment = findFirst (att: att.nixDaemonIntegration) null (attrValues activeAttachments);
in
{
  options.services.build-cache = {
    attachments = mkOption {
      type = types.attrsOf (types.submodule attachmentSubmodule);
      default = { };
      description = "List of NFS loopback image attachments.";
    };
  };

  config = mkIf (activeAttachments != { }) (mkMerge [
    {
      fleet.waitForHost = mkMerge (
        mapAttrsToList (name: att: {
          "${name}" = {
            host = head (splitString ":" att.nfsDevice);
          };
        }) activeAttachments
      );

      fileSystems = mkMerge (
        mapAttrsToList (name: att: {
          "${att.nfsMountPoint}" = {
            device = att.nfsDevice;
            fsType = "nfs";
            options = [
              "nfsvers=4.2"
              "_netdev"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=600"
              "x-systemd.requires=wait-for-host-${name}.service"
              "x-systemd.after=wait-for-host-${name}.service"
            ];
          };

          "${att.targetMountPoint}" = {
            device = "${att.nfsMountPoint}/${att.imageName}";
            fsType = "ext4";
            options = [
              "loop"
              "nofail"
              "x-systemd.requires=nix-build-img-init-${name}.service"
              "x-systemd.after=nix-build-img-init-${name}.service"
            ];
          };
        }) activeAttachments
      );

      systemd.services = mkMerge (
        mapAttrsToList (name: att: {
          "nix-build-img-init-${name}" = {
            description = "Initialize loopback image for ${name} on NFS";
            after = [ "${escapeSystemdPath att.nfsMountPoint}.mount" ];
            requires = [ "${escapeSystemdPath att.nfsMountPoint}.mount" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              IMG="${att.nfsMountPoint}/${att.imageName}"
              if [ ! -f "$IMG" ]; then
                echo "Creating ${att.imageSize} sparse loopback image file..."
                truncate -s ${att.imageSize} "$IMG"
                echo "Formatting loopback image with ext4..."
                ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$IMG"
              else
                echo "Loopback image already exists. Ensuring it is ${att.imageSize}..."
                truncate -s ${att.imageSize} "$IMG"
                ${pkgs.e2fsprogs}/bin/e2fsck -fp "$IMG" || true
                ${pkgs.e2fsprogs}/bin/resize2fs "$IMG" || true
              fi
            '';
          };

          "nix-build-permissions-${name}" = {
            description = "Ensure ${name} build directory has correct permissions";
            after = [ "${escapeSystemdPath att.targetMountPoint}.mount" ];
            requires = [ "${escapeSystemdPath att.targetMountPoint}.mount" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              chown ${att.owner}:${att.group} ${att.targetMountPoint}
              chmod ${att.mode} ${att.targetMountPoint}
            '';
          };
        }) activeAttachments
      );
    }

    (mkIf (nixDaemonAttachment != null) {
      systemd.services.nix-daemon = {
        environment = {
          TMPDIR = nixDaemonAttachment.targetMountPoint;
        };
        serviceConfig = {
          RequiresMountsFor = [ nixDaemonAttachment.targetMountPoint ];
        };
      };

      environment.variables.TMPDIR = nixDaemonAttachment.targetMountPoint;

      nix.settings = {
        min-free = 2 * 1024 * 1024 * 1024; # 2GB
        max-free = 6 * 1024 * 1024 * 1024; # 6GB
      };
    })
  ]);
}
