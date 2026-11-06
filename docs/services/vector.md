# Vector

Vector ships each host's journal to Loki on `proxmox-observability-debian`
and exposes its own metrics on `:9598`. Decision:
[2026-11-06-shared-vector-pipeline](../adr/2026-11-06-shared-vector-pipeline.md).
Earlier choice of Vector over Alloy:
[2026-09-08-vector-replaces-alloy](../adr/2026-09-08-vector-replaces-alloy.md).

## One pipeline, four renders

| Consumer | Where it is defined | Host label |
|---|---|---|
| NixOS hosts (`xcloud-*`, `gaming`) | `config/observability.nix` | `networking.hostName` |
| Debian guests | `fleet.debian_guest` role `monitoring`, `templates/vector.yaml.j2` | `debian_guest_tailscale_hostname` |
| Proxmox host | `ansible/roles/vector/templates/vector.yaml.j2` | `proxmox` |

All three read two shared files:

- `config/vector/journal-remap.vrl`: the journal remap. `@host@` is
  replaced per host. Postgres log parsing stays in
  `config/observability.nix` because only the Postgres host has that source.
- `config/vector/loki-sink.json`: labels (`job`, `host`, `service`,
  `syslog_id`, `syslog_facility`), the 256 MiB disk buffer that blocks when
  full, JSON encoding, and `out_of_order_action: accept`.

Each consumer sets only `inputs` and `endpoint` on the sink and its own
`journald` source. NixOS hosts read the whole journal
(`current_boot_only = false`). Debian trixie is systemd 257, where Vector
0.57 rejects that, so the Debian guests and the Proxmox host use `true`.

## Change the pipeline

Edit the shared file, then run `make check-vector-config`. It renders every
consumer, fails if one differs from the shared files, and runs
`vector validate` on each render. On Darwin, set `ALLOW_NO_VECTOR=1` to skip
the validate step; CI runs it.

Roll out with `make deploy-host HOST=...` (NixOS), `make deploy-debian-*`
(guests), and `make deploy-proxmox-host` (hypervisor). A Vector restart
re-reads the journal cursor, so no lines are lost.

## Memory

`MemoryHigh=192M` / `MemoryMax=256M` fleet default; `xcloud-postgres` is
lower (see [memory.md](../memory.md)). A Loki outage fills the disk buffer, not the
heap.

## Alerting

- `VectorTargetDown`: Prometheus cannot scrape `:9598`.
- `LokiClientDrops`: Vector dropped or failed Loki writes.

Dashboard: `fleet-vector`. See [monitoring.md](../monitoring.md) and
[loki.md](loki.md).
