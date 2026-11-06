# Pure function: hostname -> NixOS module paths from fleet/apps.
# flake.nix calls this so heavy modules are only imported on the host
# that runs them.
lib: hostname:
let
  appsDir = ../fleet/apps;
  appFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (
    builtins.readDir appsDir
  );
  paths = lib.concatLists (
    lib.mapAttrsToList (
      file: _:
      let
        app = import (appsDir + "/${file}");
        extra = app.extraHosts or [ ];
        onHost = (app.host or "") == hostname || lib.elem hostname extra;
        mod = app.module or null;
      in
      lib.optional (onHost && mod != null) (../. + "/${mod}")
    ) appFiles
  );
in
lib.unique paths
