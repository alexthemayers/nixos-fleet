---
status: accepted
date: 2026-09-09
---

# Radarr and Sonarr own movie and show acquisition

## Context and Problem Statement

Jellyfin identification for this fleet lived in sidecar NFO files
([2026-09-08-jellyfin-sidecar-nfo](2026-09-08-jellyfin-sidecar-nfo.md)).
That ADR forbade introducing *arr just for metadata and forbade
mass-renaming movie folders that already had `movie.nfo`. The operator
now wants torrent acquisition, quality upgrades, and library rename
automated for the existing Movies and Shows libraries. How should this
fleet acquire and rename those libraries?

## Decision Drivers

* New drops should land as one title per folder without a manual
  `downloads/` promote.
* The existing Movies and Shows libraries will be imported and renamed.
* Anime stays AniDB-first. Documentaries stay on the sidecar-NFO flow.
* No public DNS for the *arr UIs yet. Tailnet access is enough.
* The operator accepted torrenting without a VPN: this host's public IP
  is visible in swarms.

## Considered Options

* Keep the sidecar-NFO ingest loop only (no *arr)
* Radarr / Sonarr / Prowlarr / qBittorrent on `proxmox-applications-1`,
  tailnet-only, no VPN; import the existing Movies and Shows libraries
* Same stack plus a VPN killswitch
* Usenet (SABnzbd) instead of torrents

## Decision Outcome

Chosen option: "Radarr / Sonarr / Prowlarr / qBittorrent on
`proxmox-applications-1`, tailnet-only, no VPN; import the existing
Movies and Shows libraries", because the operator wants automated
grabs, upgrades, and renames on the share Jellyfin already mounts.

This supersedes the "do not introduce *arr" and "do not mass-rename
movie folders that already have `movie.nfo`" clauses of
[2026-09-08-jellyfin-sidecar-nfo](2026-09-08-jellyfin-sidecar-nfo.md).
Sidecar NFO remains the durable ID for Anime and Documentaries. Jellyfin
still writes NFO after a Radarr/Sonarr import. Never "Replace all
metadata" on a Jellyfin library.

qBittorrent has no VPN or gluetun. Revisit if the public IP in swarms
becomes unacceptable. Public Caddy vhosts (per-vhost oauth2-proxy) wait
until DNS exists
([2026-08-29-oauth2-proxy-coverage](2026-08-29-oauth2-proxy-coverage.md)).

### Consequences

* Good, because new Movies and Shows titles import as one folder with
  Radarr/Sonarr naming and a TMDB match.
* Good, because quality upgrades and missing-episode grabs are automatic
  after the one-time pairing.
* Bad, because renaming existing folders can reset Jellyfin watch
  progress and orphan trickplay for those titles.
* Bad, because qBittorrent's peer traffic leaves this VM's WAN IP with
  no killswitch.
* Bad, because Radarr matches imports by folder name, not the existing
  sidecar `tmdbid`. Scene-named folders need a careful import.

## Validation

Module: [services/media-automation](../../services/media-automation).
Host: `proxmox-applications-1` only. UIs on the tailnet: Radarr `:7878`,
Sonarr `:8989`, Prowlarr `:9696`, qBittorrent `:8081`. Blackbox job
`blackbox_http_internal`. Runbook:
[media-automation.md](../runbooks/media-automation.md).

## More Information

Service doc: [media-automation.md](../services/media-automation.md).
Manual ingest for anime and documentaries:
[jellyfin-metadata.md](../runbooks/jellyfin-metadata.md).
