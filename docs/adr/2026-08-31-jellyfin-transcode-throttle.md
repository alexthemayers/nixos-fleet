# ADR: Jellyfin transcode throttling stays on

**Status:** accepted (2026-08-31)

## Context

Unthrottled 4K QSV HLS on apps-1 encodes at ~15× realtime. On the dedicated
SSD NFS cache (`truenas-scale:/mnt/ssd/jellyfin/cache`) that wrote ~1.5 GiB in
120 s at 3.3% avg guest iowait. The same job on the 35 G VM root was worse
(5.7%, 1.5 GiB gone from `/`). With `ffmpeg -re` (realtime analogue of
throttling) iowait dropped to idle on that NFS dest and Jellyfin stayed up
(121/121 HTTP probes).

`encoding.xml` on the config NFS share is dashboard-editable. Leaving
`EnableThrottling` off after a UI save would restore the 15× fill.

## Decision

Keep **EnableThrottling** on in the Nix-managed `encoding.xml`
(`ThrottleDelaySeconds` 180, `SegmentKeepSeconds` 720). A dashboard
uncheck does not survive restart because the file is overlaid from the
store. See [2026-09-04-jellyfin-declarative-config](2026-09-04-jellyfin-declarative-config.md).

## Consequences

Do not turn throttling off in `encoding.xml` without amending this ADR.
Hardware encoder settings live in the same Nix-managed file; change them
in `services/jellyfin/config/encoding.xml` and deploy. Do not enable
nixpkgs `services.jellyfin.forceEncodingConfig` — that XML is a subset
and would drop QSV / VPP / throttle timing. See
[jellyfin.md](../services/jellyfin.md).
