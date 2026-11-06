{ ... }:
{
  networking.hostName = "rpi4";
  system.stateVersion = "25.11";

  # aarch64 paths are not all on cache.nixos.org. system.nix already
  # mkForce's the public cache and its key; these add the Pi cachix.
  nix.settings.extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  ];

  # Tombstones. Dropping the old modules is not enough: systemd can start
  # leftover units from a previous generation during switch. rpi4 was
  # unreachable when !15 tried to remove these; keep them until a live
  # switch confirms the units are gone (systemctl list-unit-files).
  systemd.services.loki.enable = false;
  systemd.services.loki-cluster-env.enable = false;
  systemd.services.mimir.enable = false;
  systemd.services.mimir-cluster-env.enable = false;
  systemd.services.grafana.enable = false;
  systemd.services.prometheus.enable = false;
  systemd.services.alertmanager.enable = false;
  systemd.services.alertmanager-cluster-env.enable = false;
  systemd.services.alertmanager-ntfy.enable = false;
  systemd.services.ntfy-sh.enable = false;
  systemd.services.ntfy-custom-setup.enable = false;
  systemd.services.garage.enable = false;
  systemd.services.keycloak.enable = false;
  systemd.services.prometheus-blackbox-exporter.enable = false;
}
