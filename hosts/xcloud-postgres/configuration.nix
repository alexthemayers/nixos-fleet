{ lib, ... }:
{
  networking.hostName = "xcloud-postgres";
  fleet.services.redis.enable = true;

  # Fleet Alloy cap is 512M, sized for 4 GiB obs VMs. This hub still
  # overrides below that. 160M/96MiB hit MemoryHigh continuously while
  # tailing journal (audit flood) and reread the disk. See
  # docs/adr/2026-09-08-xcloud-postgres-alloy-cap.md.
  systemd.services.alloy = {
    environment = {
      GOMEMLIMIT = "192MiB";
      GOMAXPROCS = "1";
    };
    serviceConfig = {
      MemoryHigh = lib.mkForce "320M";
      MemoryMax = lib.mkForce "384M";
      OOMScoreAdjust = 300;
    };
  };

  # Prefer killing a runaway exporter over Postgres.
  systemd.services.postgresql.serviceConfig.OOMScoreAdjust = -300;

  systemd.services.prometheus-node-exporter.serviceConfig.MemoryMax = "48M";
  systemd.services.prometheus-postgres-exporter.serviceConfig.MemoryMax = "48M";
  systemd.services.prometheus-pgbouncer-exporter.serviceConfig.MemoryMax = "48M";
  systemd.services.prometheus-redis-exporter.serviceConfig.MemoryMax = "48M";
  systemd.services.prometheus-systemd-exporter.serviceConfig.MemoryMax = "48M";
  systemd.services.prometheus-smokeping-exporter.serviceConfig.MemoryMax = "64M";
}
