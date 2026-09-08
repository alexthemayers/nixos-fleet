# Runbook: Jellyfin library identification

Sidecar NFO is the durable ID
([2026-09-08-jellyfin-sidecar-nfo](../adr/2026-09-08-jellyfin-sidecar-nfo.md)).
Media lives on `truenas-scale:/mnt/hdd/media`, mounted on
`proxmox-applications-1` at `/mnt/nfs/media`. Do not `chown` the
Jellyfin config dataset.

## Ingest (new titles)

```
/mnt/nfs/media/movies/Title (Year)/Title (Year).mkv
/mnt/nfs/media/series/Title (Year)/Season 01/Title (Year) - S01E01 - Episode.mkv
/mnt/nfs/media/anime/Title/Season 01/...
/mnt/nfs/media/documentaries/Title (Year)/...
```

Scene-release folder names are fine only after Identify has written
`movie.nfo` or `tvshow.nfo` with a `tmdbid` (anime: `anidbid`). One
movie per folder. Season packs must be `Season NN`, not
`Show.S01.COMPLETE…`.

## Correct a wrong match

1. In the dashboard, Identify the item (search TMDB; anime: AniDB).
2. Confirm the sidecar now has the right id and `lockdata` is true.
3. Refresh **this item** only. Do not "Replace all metadata".
4. If the NFO is wrong, delete that NFO (not the video), Identify
   again, then lock.

Dashboard edits to `services/jellyfin/**/*.xml` do not survive a
restart. Change fetchers in git and deploy apps-1.

## Split a multi-movie folder

On `proxmox-applications-1`, same dataset (rename, not copy):

```bash
src='/mnt/nfs/media/movies/Some Collection'
mkdir -p '/mnt/nfs/media/movies/Title (Year)'
mv "$src/Title.mkv" "$src/Title.trickplay" \
  '/mnt/nfs/media/movies/Title (Year)/'
# write movie.nfo with tmdbid, or Identify after the next scan
```

Leave an empty collection folder only after every video has moved.
Realtime monitor will pick the new paths up.

## Flatten a season pack

```bash
show='/mnt/nfs/media/series/Some Show'
mv "$show/Some.Show.S02.COMPLETE..." "$show/Season 02"
```

Abort if `Season 02` already exists. Move trickplay with the videos
(they sit inside the pack directory).

## Do not

- Mass-rename movie folders that already have `movie.nfo`.
- Extract or delete unrelated rarsets (`War.of.the.Worlds.2025…` is
  not a playable library item until it is an mkv).
- Run `nix-shell` on this host to pull helper tools.
- `chown` `/mnt/nfs/jellyfin/config`.
