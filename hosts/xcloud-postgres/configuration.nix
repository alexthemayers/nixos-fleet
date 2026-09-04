{ lib, ... }:
{
  networking.hostName = "xcloud-postgres";
  fleet.services.redis.enable = true;

  # Fleet Alloy cap is 512M, sized for 4 GiB obs VMs. This hub is 1 GiB;
  # Alloy was ~265M RSS and the second-largest resident after Postgres.
  # GOMEMLIMIT is a soft heap target so the cgroup kill is not the first
  # backpressure. See docs/adr/2026-09-04-xcloud-postgres-1g.md.
  systemd.services.alloy = {
    environment = {
      GOMEMLIMIT = "96MiB";
      GOMAXPROCS = "1";
    };
    serviceConfig = {
      MemoryHigh = lib.mkForce "112M";
      MemoryMax = lib.mkForce "160M";
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
  systemd.services.prometheus-smokeping-prober.serviceConfig.MemoryMax = "64M";
}
