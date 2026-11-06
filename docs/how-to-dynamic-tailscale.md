# How-To: Dynamic Tailscale IP Injection

Do not hardcode Tailscale IPs in Nix or Ansible. Resolve `tailscale0` at
unit start into an `EnvironmentFile` (or equivalent) when a daemon must
advertise its mesh address.

## Pattern

systemd loads `EnvironmentFile` **before** `ExecStartPre`, so a pre-script
on the daemon cannot create the file the daemon is about to read. A
separate oneshot writes `/run/<name>-cluster.env`, then the daemon
`Requires=` / `After=` that oneshot.

The fleet used to ship this as `fleet.clusterEnv`
([custom-options.md](custom-options.md#cluster-gossip-address-fleetclusterenv--deleted)).
That option is gone: Loki, Mimir, and Alertmanager no longer run on NixOS
hosts. Copy the oneshot pattern below when you add a clustered daemon.

```nix
# Illustrative; not a live module.
systemd.services.my-cluster-env = {
  description = "Resolve the tailscale0 address my-daemon gossips on";
  before = [ "my-daemon.service" ];
  requiredBy = [ "my-daemon.service" ];
  after = [ "tailscaled.service" "network-online.target" ];
  wants = [ "tailscaled.service" "network-online.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = pkgs.writeShellScript "my-cluster-env" ''
      set -euo pipefail
      ip=""
      for _ in $(seq 1 60); do
        ip=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null | head -n1 || true)
        [ -n "$ip" ] && break
        sleep 1
      done
      [ -n "$ip" ] || { echo "tailscale0 has no IPv4" >&2; exit 1; }
      umask 077
      echo "MY_CLUSTER_IP=$ip" > /run/my-cluster.env
    '';
  };
};
systemd.services.my-daemon.serviceConfig.EnvironmentFile = [ "/run/my-cluster.env" ];
```

The oneshot retries until `tailscale0` has an IPv4 address or the timeout
elapses, then fails the unit. The daemon expands the variable in its
config (`-config.expand-env=true` or the equivalent).

## Do not override ExecStart with a polling loop

An earlier pattern replaced `ExecStart` with a `/bin/sh -c` string containing
an unbounded `while ! ip addr show dev tailscale0; do sleep 1; done` loop
before `exec`ing the daemon.

That is worse in three ways:

- **It never fails.** A host where `tailscaled` does not come up sits in
  `activating` forever. systemd `Restart=`, start limits, and unit-failure
  alerts never trigger.
- **The shell becomes PID 1**, so signals and exit statuses belong to `sh`.
- **It discards upstream `ExecStart`**, including flags the NixOS module
  derives. Those drift when the module updates.

Do not put the resolver in `ExecStartPre` on the daemon either: the
`EnvironmentFile` is already required before that pre-script runs.

## Tradeoffs

- **Pros**: IP changes need no Nix edit. The oneshot fails visibly when the
  mesh is down. Upstream `ExecStart` stays intact.
- **Cons**: The address is resolved at start. A live Tailscale IP change
  needs a restart. The application must expand environment variables in
  config.
