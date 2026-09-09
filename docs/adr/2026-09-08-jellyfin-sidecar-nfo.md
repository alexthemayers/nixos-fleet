---
status: superseded by [2026-09-09-arr-stack-acquisition.md](2026-09-09-arr-stack-acquisition.md)
date: 2026-09-09
---

# Jellyfin identification lives in sidecar NFO files

## Context and Problem Statement

Jellyfin on `proxmox-applications-1` already had Kodi-style `movie.nfo` /
`tvshow.nfo` next to most titles, with TMDB and IMDb IDs. The declarative
library XML did not treat those files as the contract: Shows and
Documentaries fetched AniDB first, Movies trusted embedded MKV titles,
`SaveLocalMetadata` was off, and `MetadataCountryCode` was `ZA`. A
library rebuild or "replace all metadata" could re-guess from
scene-release folder names and lose a correct match. `library.db` on the
config NFS share is not a durable record.

How should this fleet keep series and movie identification correct
across scans, rebuilds, and new drops?

## Decision Drivers

* Most titles already have sidecar IDs; the scanner must not override
  them.
* Anime and Western TV must not share a primary provider.
* Mass-renaming hundreds of movie folders on HDD NFS would orphan
  trickplay dirs and reset watch state for no identification gain.
* Dashboard Identify is lost unless it writes an NFO
  ([2026-09-04-jellyfin-declarative-config](2026-09-04-jellyfin-declarative-config.md)).

## Considered Options

* Sidecar NFO with provider IDs as the source of truth; Jellyfin writes
  and reads them
* Radarr / Sonarr rename-and-NFO pipeline
* Mass FileBot rename of every movie and show folder
* Jellyfin `library.db` only (Identify in the dashboard)

## Decision Outcome

Chosen option: "Sidecar NFO with provider IDs as the source of truth",
because the IDs are already on the media share and survive a library
rebuild. Movies, Shows, and Documentaries use TMDB (OMDb fallback).
Anime stays AniDB-first. Jellyfin saves local NFO. Embedded titles stay
off. Matching country is `US`, language `en`.

Movies and Shows acquisition, rename, and quality upgrades moved to
Radarr/Sonarr
([2026-09-09-arr-stack-acquisition](2026-09-09-arr-stack-acquisition.md)).
Anime and Documentaries still use this sidecar-NFO contract. Flatten
season packs to `Season NN` and split multi-movie folders when the path
itself cannot be parsed. Never "Replace all metadata" on a library.

### Consequences

* Good, because a correct `tmdbid` / `anidbid` rematches after
  `library.db` loss.
* Good, because new Identify in the dashboard persists next to the
  file.
* Bad, because `SaveLocalMetadata` writes NFO and images onto the
  HDD media dataset (trickplay already did this for Shows).
* Bad, because splitting collections and renaming season packs
  changes paths and can reset watch progress for those titles.

## Validation

Library XML under `services/jellyfin/libraries/*/options.xml` and
`config/system.xml`. After deploy, Shows/Documentaries must not list
AniDB; Movies must have `EnableEmbeddedTitles` false and
`SaveLocalMetadata` true. Runbook:
[jellyfin-metadata.md](../runbooks/jellyfin-metadata.md).

## More Information

Service doc: [jellyfin.md](../services/jellyfin.md).
