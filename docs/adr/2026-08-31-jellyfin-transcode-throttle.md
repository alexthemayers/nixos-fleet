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

Keep **EnableThrottling** on. `jellyfin.service` `preStart` rewrites
`<EnableThrottling>false</EnableThrottling>` to `true` so a dashboard uncheck
does not survive a restart.

Leave `ThrottleDelaySeconds` (180) and `SegmentKeepSeconds` (720) at the
values already on this host. Those are Jellyfin defaults: encode until the
player is three minutes ahead, keep twelve minutes of HLS segments. That is
enough to stop a 15× run from filling the cache for the whole title. Tighter
values (20 / 60) were used only for a 2 GiB tmpfs experiment.

## Consequences

Do not turn throttling off in `encoding.xml` without amending this ADR.
Hardware encoder settings in the same file stay host-managed; do not replace
the whole XML from the Nix store. See [jellyfin.md](../services/jellyfin.md).
