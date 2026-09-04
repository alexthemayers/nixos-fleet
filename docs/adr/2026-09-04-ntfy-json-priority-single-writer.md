# ADR: ntfy JSON priority is an integer; one writer node

**Status:** accepted (2026-09-04)

## Context

Both observability VMs run Alertmanager and ntfy-sh. The group webhook
POSTs JSON to ntfy. ntfy’s JSON publisher unmarshals `priority` as `int`
(1–5). String values (`urgent`, `high`) are valid only as HTTP headers.
A JSON string is rejected as **40024** (`request body must be valid JSON`),
so every alert failed to page.

Caddy `lb_policy first` sends phone clients to obs-1. Each Alertmanager
posted to **localhost** ntfy, so a notification elected on obs-2 never
reached subscribers.

## Decision

- JSON `priority` is an integer: resolved=3, critical=5, warning=4, info=2.
- Omit `click` unless it is an absolute `http://` or `https://` URL (Mimir
  ruler emits `/graph?...`).
- Both webhooks publish to `proxmox-observability-1:2586`. ntfy stays two
  daemons with local SQLite; clustering is not in scope.

## Consequences

Paging depends on obs-1 ntfy. If that process is down, Caddy can fail over
to obs-2 for **subscribers**, but Alertmanager still writes obs-1 until
that node is drained. Duplicate ntfy user DBs are not synced.
