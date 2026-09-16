---
status: accepted
date: 2026-09-11
---

# Radarr and Sonarr write Movies/Shows NFO and refresh Jellyfin

## Context and Problem Statement

Movies and Shows acquisition already lives in Radarr and Sonarr
([2026-09-09-arr-stack-acquisition](2026-09-09-arr-stack-acquisition.md)).
That ADR still had Jellyfin write sidecar NFO after import, and Connect
was empty. New and upgraded files could sit on disk until the next
Jellyfin scan, and *arr did not own the `movie.nfo` / `tvshow.nfo` IDs
it had just matched. The operator wants *arr to rewrite those NFOs and
to tell Jellyfin immediately.

## Decision Drivers

* In-place upgrades keep the same path; a realtime NFS watch can miss
  them.
* The operator accepted *arr overwriting existing Movies/Shows NFOs.
* Anime and Documentaries stay off *arr.

## Considered Options

* Leave NFO writes to Jellyfin; rely on the realtime monitor
* Enable Kodi/XBMC metadata in Radarr/Sonarr and MediaBrowser Connect
  to local Jellyfin
* Enable metadata only, no Connect

## Decision Outcome

Chosen option: "Enable Kodi/XBMC metadata in Radarr/Sonarr and
MediaBrowser Connect to local Jellyfin", because *arr already has the
TMDB/TVDB match and Jellyfin should see the new file without a manual
scan.

Radarr writes `movie.nfo` (`useMovieNfo`) plus poster/fanart. Sonarr
writes `tvshow.nfo`, episode `.nfo`, and series/season/episode images.
Connect (`127.0.0.1:8096`) updates the library on import, upgrade,
rename, and delete. `notify` stays off (Emby-only). Live pairing, not
Nix. Anime and Documentaries are unchanged
([2026-09-08-jellyfin-sidecar-nfo](2026-09-08-jellyfin-sidecar-nfo.md)).
Do not "Replace all metadata" on a Jellyfin library.

This replaces the "Jellyfin still writes NFO after a Radarr/Sonarr
import" sentence in
[2026-09-09-arr-stack-acquisition](2026-09-09-arr-stack-acquisition.md).

### Consequences

* Good, because a rename or upgrade refreshes Jellyfin on that path.
* Good, because Movies/Shows sidecar IDs match what *arr imported.
* Bad, because a Refresh in Radarr/Sonarr rewrites existing NFOs and
  artwork on the media share.

## Validation

Live Connect name `Jellyfin` on Radarr `:7878` and Sonarr `:8989`.
Kodi/XBMC metadata enabled. Runbook:
[media-automation.md](../runbooks/media-automation.md).

## More Information

Service doc: [media-automation.md](../services/media-automation.md).
Subtitles: [2026-09-11-bazarr-external-subs](2026-09-11-bazarr-external-subs.md).
