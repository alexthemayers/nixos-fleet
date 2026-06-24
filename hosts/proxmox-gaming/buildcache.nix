{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Wait for TrueNAS MagicDNS resolution before mounting NFS
  systemd.services.wait-for-nas-build = {
    description = "Wait for TrueNAS MagicDNS resolution for Nix Build NFS";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    script = ''
      for i in {1..120}; do
        if ${pkgs.iputils}/bin/ping -c 1 -W 1 truenas-scale >/dev/null 2>&1; then
          echo "TrueNAS is reachable!"
          exit 0
        fi
        echo "Waiting for MagicDNS..."
        sleep 1
      done
      exit 1
    '';
  };

  # Mount the NFS share containing the loopback image
  fileSystems."/mnt/nfs/nix-build" = {
    device = "truenas-scale:/mnt/ssd/buildcache";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=wait-for-nas-build.service"
      "x-systemd.after=wait-for-nas-build.service"
    ];
  };

  # Initialize the sparse 100GB loopback image if it doesn't exist, and resize if needed
  systemd.services.nix-build-img-init = {
    description = "Initialize Nix build loopback image on NFS";
    after = [ "mnt-nfs-nix\\x2dbuild.mount" ];
    requires = [ "mnt-nfs-nix\\x2dbuild.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      IMG="/mnt/nfs/nix-build/nix-build.img"
      if [ ! -f "$IMG" ]; then
        echo "Creating 100GB sparse loopback image file..."
        truncate -s 100G "$IMG"
        echo "Formatting loopback image with ext4..."
        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$IMG"
      else
        echo "Loopback image already exists. Ensuring it is 100GB..."
        truncate -s 100G "$IMG"
        ${pkgs.e2fsprogs}/bin/e2fsck -fp "$IMG" || true
        ${pkgs.e2fsprogs}/bin/resize2fs "$IMG" || true
      fi
    '';
  };

  # Mount the loopback image onto /nix/var/nix/builds
  fileSystems."/nix/var/nix/builds" = {
    device = "/mnt/nfs/nix-build/nix-build.img";
    fsType = "ext4";
    options = [
      "loop"
      "nofail"
      "x-systemd.requires=nix-build-img-init.service"
      "x-systemd.after=nix-build-img-init.service"
    ];
  };

  # Ensure Nix build directory has the correct write permissions for all build users
  systemd.services.nix-build-permissions = {
    description = "Ensure Nix build directory has correct permissions";
    after = [ "nix-var-nix-builds.mount" ];
    requires = [ "nix-var-nix-builds.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      chown root:nixbld /nix/var/nix/builds
      chmod 1775 /nix/var/nix/builds
    '';
  };

  # Configure nix-daemon to use the loopback mount for build compilation
  systemd.services.nix-daemon = {
    environment = {
      TMPDIR = "/nix/var/nix/builds";
    };
    serviceConfig = {
      RequiresMountsFor = [ "/nix/var/nix/builds" ];
    };
  };

  # Set TMPDIR globally for all sessions (including non-interactive SSH remote builder sessions)
  environment.variables.TMPDIR = "/nix/var/nix/builds";

  # Auto-GC when free space in /nix/store is low
  nix.settings = {
    min-free = 2 * 1024 * 1024 * 1024; # 2GB
    max-free = 6 * 1024 * 1024 * 1024; # 6GB
  };
}
