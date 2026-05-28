{
  config,
  pkgs,
  libs,
  ...
}:
{
  networking.firewall = {
    interfaces."tailscale0" = {
      allowedTCPPorts = [
        111 # RPC Portmapper
        2049 # NFS
        4000
        4001
        4002 # Statd, Lockd, Mountd (Standard ports)
        20048 # Mountd
      ];
      allowedUDPPorts = [
        111
        2049
        4000
        4001
        4002
        20048
      ];
    };
  };
}
