{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.minetest-server = {
    enable = true;
    port = 30000;
    gameId = "mineclonia";
    config = {
      name = "alex";
    };
  };

  systemd.services.minetest-server.preStart = lib.mkBefore ''
    mkdir -p /var/lib/minetest/.minetest/games/mineclonia
    if [ ! -f /var/lib/minetest/.minetest/games/mineclonia/game.conf ]; then
      ${pkgs.curl}/bin/curl -sL https://codeberg.org/mineclonia/mineclonia/archive/main.tar.gz | ${pkgs.gzip}/bin/gzip -d | ${pkgs.gnutar}/bin/tar -x -C /var/lib/minetest/.minetest/games/mineclonia --strip-components=1
    fi
    ${pkgs.findutils}/bin/find /var/lib/minetest/.minetest/games/mineclonia -name "*.po" -type f -delete
  '';

  networking.firewall.allowedUDPPorts = [ 30000 ];
}
