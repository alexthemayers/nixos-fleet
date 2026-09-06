# How-To: Dynamic Tailscale IP Injection

Clustered applications (Loki, Mimir, Alertmanager) peer over `tailscale0`.
Do not hardcode Tailscale IPs in Nix. Resolve `tailscale0` at unit start into
an `EnvironmentFile`.

## Use `fleet.clusterEnv`

systemd loads `EnvironmentFile` **before** `ExecStartPre`, so a pre-script on
the daemon cannot create the file the daemon is about to read. A separate
oneshot writes `/run/<name>-cluster.env`, then the daemon `Requires=` /
`After=` that oneshot.

Schema: [custom-options.md](custom-options.md#cluster-gossip-address-fleetclusterenv).
Implementation: [config/cluster-env.nix](../config/cluster-env.nix).

```nix
fleet.clusterEnv.loki = {
  service = "loki.service";
  envFile = "/run/loki-cluster.env";
  ipVariable = "LOKI_CLUSTER_IP";
  timeoutSec = 60;
};
```

The oneshot retries until `tailscale0` has an IPv4 address or `timeoutSec`
elapses, then fails the unit. The daemon expands the variable in its config
(`-config.expand-env=true` or the equivalent).

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
