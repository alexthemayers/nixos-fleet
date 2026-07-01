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

  fileSystems."/mnt/nfs/luanti" = {
    device = "truenas-scale:/mnt/ssd/luanti";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=wait-for-host-luanti.service"
      "x-systemd.after=wait-for-host-luanti.service"
    ];
  };

  fleet.waitForHost.luanti.host = "truenas-scale";

  systemd.services.minetest-server = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/luanti" ];
      BindPaths = [ "/mnt/nfs/luanti:/var/lib/minetest" ];
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
