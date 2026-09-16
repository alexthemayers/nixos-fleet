---
status: accepted
date: 2026-09-11
---

# Bazarr writes external text subtitles for Movies and Shows

## Context and Problem Statement

Many library files only have PGS image subtitles. Those tracks are
awkward in Jellyfin and look burned-in. How should this fleet get
selectable text subtitles for Movies and Shows?

## Decision Drivers

* Prefer an external `.srt` over PGS.
* Anime and Documentaries stay off *arr, so they stay off Bazarr.
* No subtitle-provider credentials in Nix.

## Considered Options

* Jellyfin Open Subtitles plugin only
* Bazarr next to Radarr/Sonarr on `proxmox-applications-1`
* Tdarr remux to strip PGS and burn a text track

## Decision Outcome

Chosen option: "Bazarr next to Radarr/Sonarr on
`proxmox-applications-1`", because it already sees the *arr libraries
and writes `.srt` beside the video. PGS in the MKV stays; Jellyfin can
pick the text file instead.

Bazarr is tailnet-only (`:6767`). It writes under
`/mnt/nfs/media/movies` and `/mnt/nfs/media/series` only. `ignore_pgs_subs`
is on so a PGS track does not count as "already has subs". Provider
logins (OpenSubtitles.com or similar) stay in the Bazarr UI.

### Consequences

* Good, because new imports can get a text subtitle without remuxing.
* Bad, because a missing provider login means Bazarr syncs and finds
  nothing until the operator adds one.
* Bad, because PGS is still in the file; this does not strip or
  re-encode.

## Validation

Module: [services/media-automation/bazarr.nix](../../services/media-automation/bazarr.nix).
Blackbox target `http://proxmox-applications-1:6767`. Runbook:
[media-automation.md](../runbooks/media-automation.md).

## More Information

Service doc: [media-automation.md](../services/media-automation.md).
NFO and Connect:
[2026-09-11-arr-writes-nfo-and-refreshes-jellyfin](2026-09-11-arr-writes-nfo-and-refreshes-jellyfin.md).
