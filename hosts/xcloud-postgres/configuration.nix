{ lib, ... }:
{
  networking.hostName = "xcloud-postgres";
  fleet.services.redis.enable = true;

  # Fleet Vector cap is 256M. This hub stays below that so a Loki outage
  # cannot grow the forwarder until the 1 GiB target OOMs. Vector is Rust;
  # there is no GOMEMLIMIT. See
  # docs/adr/2026-09-08-vector-replaces-alloy.md.
  systemd.services.vector = {
    serviceConfig = {
      MemoryHigh = lib.mkForce "96M";
      MemoryMax = lib.mkForce "128M";
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
