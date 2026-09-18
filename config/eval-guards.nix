{
  config,
  lib,
  ...
}:
let
  # Walk hosts/<name>/**/*.nix. Path flake eval (rsync without .git) still
  # sees these files; a git flake only sees tracked ones.
  hostsRoot = ../hosts;
  hostDirs = lib.filterAttrs (_: t: t == "directory") (builtins.readDir hostsRoot);
  nixFilesIn =
    dir:
    let
      entries = builtins.readDir dir;
    in
    lib.concatLists (
      lib.mapAttrsToList (
        n: t:
        if t == "regular" && lib.hasSuffix ".nix" n then
          [ (dir + "/${n}") ]
        else if t == "directory" then
          nixFilesIn (dir + "/${n}")
        else
          [ ]
      ) entries
    );
  hostNix = lib.concatMap (name: nixFilesIn (hostsRoot + "/${name}")) (lib.attrNames hostDirs);
  # Application enablement belongs in fleet/apps and the service module.
  # Host files stay hostname, hardware, disk, and hub RAM caps.
  forbidden = [
    "fleet.apps"
    "fleet.services"
    "virtualHosts"
  ];
  hostFileHits = lib.concatMap (
    path:
    let
      text = builtins.readFile path;
      hits = lib.filter (p: lib.hasInfix p text) forbidden;
    in
    map (p: "${toString path}: ${p}") hits
  ) hostNix;

  substituterUrls =
    (config.nix.settings.substituters or [ ]) ++ (config.nix.settings.extra-substituters or [ ]);
  publicCache = lib.filter (u: lib.hasInfix "cache.nixos.org" u) substituterUrls;
in
{
  assertions = [
    {
      assertion = hostFileHits == [ ];
      message = ''
        hosts/ must not enable applications. Put host, port, and vhost in
        fleet/apps and the service module (docs/adr/2026-09-18-fleet-apps-enable-by-host.md):
        ${lib.concatStringsSep "\n" hostFileHits}
      '';
    }
    {
      assertion = publicCache == [ ];
      message = ''
        Deployed hosts must not list cache.nixos.org in nix.settings.substituters
        or extra-substituters (docs/adr/2026-08-30-attic-fill-then-exclusive.md).
        Fill may pass the public cache on the CLI. Found: ${lib.concatStringsSep ", " publicCache}
      '';
    }
  ];
}
