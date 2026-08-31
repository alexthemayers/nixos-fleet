{
  config,
  pkgs,
  ...
}:
let
  # Previously this was curl'd from .../archive/main.tar.gz at every service
  # start, unpinned and unverified: the game content could change under the
  # server on any restart, and a compromised or broken upstream would have been
  # unpacked without complaint. Pinning it makes upgrades an explicit change.
  mineclonia = pkgs.fetchzip {
    url = "https://codeberg.org/mineclonia/mineclonia/archive/0.123.0.tar.gz";
    hash = "sha256-z+aptTAGoYVhm7t2mI++noruWXqHt8iewkoO1mW7JzQ=";
    stripRoot = true;
  };
in
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
    options = import ../config/nfs-mount.nix "luanti" [ ];
  };

  fleet.waitForHost.luanti.host = "truenas-scale";

  systemd.services.minetest-server = {
    unitConfig.RequiresMountsFor = [ "/mnt/nfs/luanti" ];
    serviceConfig = {
      # World data stays on NFS; the game itself is a store path. Copying it
      # into the NFS tree on every start took longer than TimeoutStartSec and
      # failed the whole host activation.
      BindPaths = [ "/mnt/nfs/luanti:/var/lib/minetest" ];
      BindReadOnlyPaths = [
        "${mineclonia}:/var/lib/minetest/.minetest/games/mineclonia"
      ];
      # Parent of the store bind; the NFS tree may not have .minetest/games yet.
      ExecStartPre = [
        "+${pkgs.coreutils}/bin/mkdir -p /var/lib/minetest/.minetest/games"
      ];
    };
  };

  # The public edge terminates 30000/udp and forwards it here via proxmox-lb,
  # so this only needs to be reachable from the tailnet.
  networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 30000 ];
}
