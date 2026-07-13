{ pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter 0775 root node-exporter -"
  ];

  systemd.services.iperf3-speedtest-coordinator = {
    description = "Coordinated iperf3 network throughput speedtest daemon";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.iperf3
      pkgs.python3
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
      User = "root";
    };

    script = ''
      ${pkgs.python3}/bin/python3 -u - << 'EOF'
      import time
      import socket
      import subprocess
      import json
      import os
      import tempfile

      nodes = [
          "proxmox-lb",
          "proxmox-dev",
          "proxmox-db-1",
          "proxmox-db-2",
          "proxmox-applications-1",
          "proxmox-applications-2",
          "proxmox-observability-1",
          "proxmox-observability-2",
          "rpi4",
          "xcloud-caddy",
          "xcloud-postgres"
      ]

      n = len(nodes)
      total_pairs = n * (n - 1)

      # Generate directed pairs list (source, target)
      pairs = []
      for i in range(n):
          for j in range(n):
              if i != j:
                  pairs.append((nodes[i], nodes[j]))

      my_hostname = socket.gethostname().split('.')[0]
      prom_dir = "/var/lib/prometheus-node-exporter"
      prom_file = os.path.join(prom_dir, "iperf3.prom")
      daemon_prom_file = os.path.join(prom_dir, "iperf3_daemon.prom")

      # Write daemon status file immediately on startup to prevent empty directory errors in node exporter
      try:
          os.makedirs(prom_dir, exist_ok=True)
          with open(daemon_prom_file + ".tmp", "w") as f:
              f.write("# HELP node_network_throughput_iperf3_daemon_active Indicates that the iperf3 test daemon is active\n")
              f.write("# TYPE node_network_throughput_iperf3_daemon_active gauge\n")
              f.write(f"node_network_throughput_iperf3_daemon_active{{host=\"{my_hostname}\"}} 1\n")
          os.chmod(daemon_prom_file + ".tmp", 0o644)
          os.replace(daemon_prom_file + ".tmp", daemon_prom_file)
          print("Initial daemon status file written.")
      except Exception as e:
          print(f"Failed to write daemon status file: {e}")

      # Try to load existing results from the prom file to persist across restarts
      results_db = {}
      if os.path.exists(prom_file):
          try:
              with open(prom_file, "r") as f:
                  for line in f:
                      if line.startswith("node_network_throughput_iperf3_") and "target=" in line:
                          parts = line.strip().split(" ")
                          if len(parts) == 2:
                              metric_name_and_labels, val_str = parts
                              val = float(val_str) if "." in val_str else int(val_str)
                              metric_name = metric_name_and_labels.split("{")[0]
                              target = metric_name_and_labels.split('target="')[1].split('"')[0]
                              
                              if target not in results_db:
                                  results_db[target] = {"upload": 0, "download": 0, "failed": 0, "timestamp": 0}
                              
                              if metric_name == "node_network_throughput_iperf3_upload_bps":
                                  results_db[target]["upload"] = val
                              elif metric_name == "node_network_throughput_iperf3_download_bps":
                                  results_db[target]["download"] = val
                              elif metric_name == "node_network_throughput_iperf3_test_failed":
                                  results_db[target]["failed"] = val
                              elif metric_name == "node_network_throughput_iperf3_last_run_timestamp":
                                  results_db[target]["timestamp"] = int(val)
              
              results_db = {tgt: (d["upload"], d["download"], d["failed"], d["timestamp"]) for tgt, d in results_db.items()}
              print(f"Successfully loaded {len(results_db)} historical targets from {prom_file}")
          except Exception as e:
              print(f"Failed to load historical targets: {e}")
              results_db = {}

      print(f"Starting coordinated speedtest daemon on host: {my_hostname}")

      while True:
          # Sleep until the next 10-second boundary
          now = time.time()
          sleep_time = 10 - (now % 10)
          time.sleep(sleep_time)
          
          epoch = int(time.time())
          slot = epoch // 10
          pair_idx = slot % total_pairs
          
          source_node, target_node = pairs[pair_idx]
          
          if my_hostname == source_node:
              print(f"[{epoch}] My turn to run speedtest targeting: {target_node}")
              upload_bps = 0
              download_bps = 0
              failed = 0
              
              try:
                  is_local = source_node.startswith("proxmox-") and target_node.startswith("proxmox-")
                  cmd = ["iperf3", "-c", target_node, "-t", "2", "-J"]
                  if not is_local:
                      cmd += ["-b", "120M"]
                  
                  res = subprocess.run(
                      cmd,
                      capture_output=True,
                      text=True,
                      timeout=5
                  )
                  if res.returncode == 0:
                      data = json.loads(res.stdout)
                      upload_bps = data.get("end", {}).get("sum_sent", {}).get("bits_per_second", 0)
                      download_bps = data.get("end", {}).get("sum_received", {}).get("bits_per_second", 0)
                  else:
                      print(f"iperf3 test failed: {res.stderr}")
                      failed = 1
              except subprocess.TimeoutExpired:
                  print("iperf3 test timed out after 5 seconds")
                  failed = 1
              except Exception as e:
                  print(f"Unexpected error running speedtest: {e}")
                  failed = 1
                  
              try:
                  # Update the database
                  results_db[target_node] = (upload_bps, download_bps, failed, epoch)
                  
                  os.makedirs(prom_dir, exist_ok=True)
                  with tempfile.NamedTemporaryFile("w", dir=prom_dir, delete=False) as tf:
                      tf.write("# HELP node_network_throughput_iperf3_upload_bps Active network upload throughput in bps\n")
                      tf.write("# TYPE node_network_throughput_iperf3_upload_bps gauge\n")
                      for tgt, (up, down, fail, ts) in results_db.items():
                          tf.write(f"node_network_throughput_iperf3_upload_bps{{target=\"{tgt}\"}} {up}\n")
                          
                      tf.write("# HELP node_network_throughput_iperf3_download_bps Active network download throughput in bps\n")
                      tf.write("# TYPE node_network_throughput_iperf3_download_bps gauge\n")
                      for tgt, (up, down, fail, ts) in results_db.items():
                          tf.write(f"node_network_throughput_iperf3_download_bps{{target=\"{tgt}\"}} {down}\n")
                          
                      tf.write("# HELP node_network_throughput_iperf3_test_failed Indicates if the last iperf3 speedtest failed\n")
                      tf.write("# TYPE node_network_throughput_iperf3_test_failed gauge\n")
                      for tgt, (up, down, fail, ts) in results_db.items():
                          tf.write(f"node_network_throughput_iperf3_test_failed{{target=\"{tgt}\"}} {fail}\n")
                          
                      tf.write("# HELP node_network_throughput_iperf3_last_run_timestamp Unix timestamp of the last speedtest run\n")
                      tf.write("# TYPE node_network_throughput_iperf3_last_run_timestamp gauge\n")
                      for tgt, (up, down, fail, ts) in results_db.items():
                          tf.write(f"node_network_throughput_iperf3_last_run_timestamp{{target=\"{tgt}\"}} {ts}\n")
                          
                      tempname = tf.name
                      
                  os.chmod(tempname, 0o644)
                  os.replace(tempname, prom_file)
              except Exception as e:
                  print(f"Failed to write prometheus metrics file: {e}")
      EOF
    '';
  };
}
