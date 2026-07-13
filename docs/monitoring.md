# Performance & Network Monitoring Architecture

This document describes the design and implementation of the network performance, latency, and system log monitoring
frameworks deployed across the `nixos-fleet` infrastructure.

---

## 📡 Distributed Bandwidth Monitoring (`iperf3-speedtest-coordinator`)

* **Implementation:** [config/network-testing.nix](file:///Users/alex/code/nixos-fleet/config/network-testing.nix)
* **Integration:** Imported via [config/observability.nix](file:///Users/alex/code/nixos-fleet/config/observability.nix)
  and deployed on **all fleet nodes**.

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

* **Implementation:** [config/observability.nix](file:///Users/alex/code/nixos-fleet/config/observability.nix)
* **Target Host:** Deployed on nodes importing the observability config.

### Design

While the speedtest measures bandwidth capacity periodically, latency and packet loss are tracked continuously using the
Prometheus Smokeping Prober.

- **Interval:** Pings targets once per second (`--ping.interval=1s`).
- **Targets:** Internal nodes, hypervisors, and external DNS (`1.1.1.1`) to establish WAN baseline metrics.
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

* **Implementation:** [config/observability.nix](file:///Users/alex/code/nixos-fleet/config/observability.nix)

The central collector utilizes Grafana **Alloy** running on port `12345` on each node to aggregate and forward telemetry
to the central cluster metrics system (`proxmox-observability-1`):

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
