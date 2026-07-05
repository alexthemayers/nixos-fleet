{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.ut2004;
  ut2004 = pkgs.callPackage ../packages/ut2004/default.nix { };
in
{
  options.programs.ut2004 = {
    enable = lib.mkEnableOption "UT2004 OldUnreal";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ ut2004 ];
  };
}
