{ ... }:
{
  networking.hostName = "rpi4";
  system.stateVersion = "25.11";

  # Tombstones. The 2026-07-24 generation still imported Loki/Mimir/Grafana/
  # Prometheus/Alertmanager/ntfy/Garage/Keycloak. Dropping those modules is
  # not enough: systemd will start the old units during switch (same class of
  # bug as wait-for-host-smokeping-* in config/observability.nix). enable =
  # false replaces each with a masked unit so activation stops them.
  # Remove once no rpi4 profile still ships those services.
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
