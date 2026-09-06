# Performance & Network Monitoring Architecture

This document describes the design and implementation of the network performance, latency, and system log monitoring
frameworks deployed across the `nixos-fleet` infrastructure.

---

## 📡 Distributed Bandwidth Monitoring (`iperf3-speedtest-coordinator`)

* **Implementation:** [config/network-testing.nix](../config/network-testing.nix)
* **Integration:** [config/observability.nix](../config/observability.nix) sets
  `fleet.networkTesting.enable = true` on every fleet host
  ([ADR](adr/2026-09-06-iperf3-mesh-on.md)).

WAN/cross-site pairs stay capped at 120 Mbps. Set
`fleet.networkTesting.enable = false` on a host only while investigating
load on that box.

### System Architecture

To continuously verify inter-node bandwidth across local networks and remote Cloud links without saturating the network
interface cards (NICs), the fleet runs a custom distributed testing daemon.

```
+-----------+                    +-----------+
|  Host A   | --- (iperf3) ----> |  Host B   |
| (Source)  |                    | (Target)  |
+-----------+                    +-----------+
      | (write .prom)
      v
[Node Exporter]
      | (scrape)
      v
[Prometheus]
```

### Execution & Scheduling Mechanics

1. **Peer List:** The daemon maintains a list of all active fleet hosts.
2. **Pairwise Matrix:** It generates a directed pair list of every source-to-target permutation.
3. **Epoch Time Slot Routing:**
    * To prevent multiple hosts from running tests simultaneously (which would corrupt bandwidth measurements),
      scheduling is derived from the Unix epoch:
      $$\text{slot} = \lfloor \frac{\text{epoch}}{10} \rfloor$$
      $$\text{pair\_index} = \text{slot} \pmod{\text{total\_pairs}}$$
    * Every 10 seconds, only the node designated as the "source" for that slot runs an active `iperf3` client test
      against the "target" node.
4. **Traffic Control:**
    * For local Proxmox-to-Proxmox virtual machines, the speedtest runs unrestricted.
    * For WAN/Tailscale targets (e.g. `xcloud-caddy` or `xcloud-postgres`), bandwidth is capped at **120 Mbps** (
      `-b 120M`) to prevent connection choking.
5. **Persistence & Reporting:**
    * Test results are written to `/var/lib/prometheus-node-exporter/iperf3.prom`.
    * The database of results persists across daemon restarts to avoid empty metrics fields.

### Exposed Metrics

* `node_network_throughput_iperf3_upload_bps{target="<host>"}`: Upload rate in bits/sec.
* `node_network_throughput_iperf3_download_bps{target="<host>"}`: Download rate in bits/sec.
* `node_network_throughput_iperf3_test_failed{target="<host>"}`: Binary gauge (1 = failed/timed out, 0 = successful).
* `node_network_throughput_iperf3_last_run_timestamp{target="<host>"}`: Timestamp of the last successful run.
* `node_network_throughput_iperf3_daemon_active{host="<host>"}`: Heartbeat monitor indicating daemon running status.

---

## ⏱️ Continuous Latency Probing (`prometheus-smokeping-prober`)

* **Implementation:** [config/observability.nix](../config/observability.nix)
* **Target Host:** Deployed on nodes importing the observability config.

### Design

While the speedtest measures bandwidth capacity periodically, latency and packet loss are tracked continuously using the
Prometheus Smokeping Prober.

- **Interval:** Pings targets once per second (`--ping.interval=1s`).
- **Targets:** Internal nodes, hypervisors, and external DNS (`1.1.1.1`) to establish WAN baseline metrics.
  `TailscaleNodeHighPacketLoss` / `HighLatency` ignore `rpi4`, `gaming`, and
  `m3pro` (same set as `TargetDown`). The probes still run.
- **Startup:** the prober no longer waits on `fleet.waitForHost` units for its targets. Making a latency prober refuse
  to start until every host it probes is reachable defeats its purpose — an unreachable target is exactly the signal it
  exists to report. It starts immediately and records failures as data.
- **Security Sandbox:** The systemd service runs as a non-root `DynamicUser` but is granted raw socket capabilities (
  `CAP_NET_RAW`) to perform ping operations safely:
  ```nix
  serviceConfig = {
    DynamicUser = true;
    CapabilityBoundingSet = [ "CAP_NET_RAW" ];
    AmbientCapabilities = [ "CAP_NET_RAW" ];
  };
  ```

---

## 🪵 Log & Metric Forwarding (`Alloy`)

* **Implementation:** [config/observability.nix](../config/observability.nix)

The central collector utilizes Grafana **Alloy** running on port `12345` on each node to aggregate and forward telemetry
to the central cluster metrics system (`proxmox-observability-1`):

0. **Write-Ahead Log (durability):** Alloy's `loki.write` endpoint has a WAL (`max_segment_age = 24h`) and retries on
   HTTP 429. The service is `MemoryMax = 512M` so a Loki outage cannot grow Alloy until the host OOMs. Without the WAL,
   any period where Loki or the internal load balancer was unavailable silently discarded logs held in memory.
   `xcloud-postgres` overrides that to `MemoryMax = 160M` and `GOMEMLIMIT=96MiB`
   so Alloy fits a 1 GiB hub
   ([ADR](adr/2026-09-04-xcloud-postgres-1g.md)).
1. **Systemd Journal Logs:**
    * Alloy parses local systemd journals.
    * Rules parse systemd units (stripping `.service` or `.scope`) to inject structured `service` and `job` labels.
    * Audit events and security failures (facilities 4 and 10) are automatically tagged with a
      `syslog_facility = "auth"` or `"audit"` label.
    * Logs are formatted into clean JSON structures and pushed to Loki.
2. **PostgreSQL JSON Logs:**
    * Reads native PostgreSQL log directories in `/var/lib/postgresql/17/log/*.json` and forwards structured database
      logs.
3. **Metrics Exporting:**
    * Prometheus Node Exporter is configured to scrape hardware statistics on port `9100`.
    * Specifies custom flags to parse textfile directory outputs:
     ```nix
     extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter" ];
     ```
    * `openFirewall = false`. The node exporter option emits a firewall rule with no interface match, which published
      port `9100` on the public NIC of the cloud VMs. `tailscale0` is already a trusted interface, so scraping across
      the tailnet is unaffected.
    * The systemd collector runs with `enable-restart-count`, which is what makes `systemd_service_restart_total`
      available — the series the crash-loop alerts are built on.

---

## Alertmanager cluster

Both observability VMs run Alertmanager with gossip on `:9094`. A split brain
sends two copies of every group to ntfy. After a deploy or a burst of duplicate
pushes:

```bash
ssh root@proxmox-observability-1 amtool --alertmanager.url=http://127.0.0.1:9093 -o extended cluster show
ssh root@proxmox-observability-2 amtool --alertmanager.url=http://127.0.0.1:9093 -o extended cluster show
```

Healthy: each node sees the other. Disk alerts are grouped by
`alertname+instance+device`. One ntfy post per group (see
[services/ntfy.md](services/ntfy.md)).
