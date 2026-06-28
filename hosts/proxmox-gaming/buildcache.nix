{ ... }:
{
  imports = [
    ../../config/build-cache.nix
  ];

  services.build-cache.attachments.nix-build = {
    enable = true;
    nfsDevice = "truenas-scale:/mnt/ssd/buildcache";
    nfsMountPoint = "/mnt/nfs/nix-build";
    imageName = "nix-build.img";
    imageSize = "100G";
    targetMountPoint = "/nix/var/nix/builds";
    owner = "root";
    group = "nixbld";
    mode = "1775";
    nixDaemonIntegration = true;
  };
}
