# Runbook: Jellyfin library identification

Sidecar NFO is the durable ID for **Anime** and **Documentaries**
([2026-09-08-jellyfin-sidecar-nfo](../adr/2026-09-08-jellyfin-sidecar-nfo.md)).
Movies and Shows acquisition is Radarr/Sonarr
([media-automation.md](media-automation.md),
[2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md)).
Media lives on `truenas-scale:/mnt/hdd/media`, mounted on
`proxmox-applications-1` at `/mnt/nfs/media`. Do not `chown` the
Jellyfin config dataset.

## Ingest (Anime and Documentaries only)

```
/mnt/nfs/media/movies/Title (Year)/Title (Year).mkv
/mnt/nfs/media/series/Title (Year)/Season 01/Title (Year) - S01E01 - Episode.mkv
/mnt/nfs/media/anime/Title/Season 01/...
/mnt/nfs/media/documentaries/Title (Year)/...
```

Scene-release folder names are fine only after Identify has written
`movie.nfo` or `tvshow.nfo` with a `tmdbid` (anime: `anidbid`). One
movie per folder. Season packs must be `Season NN`, not
`Show.S01.COMPLETE…`. Delete `Samples/` and AppleDouble `._*` before
the next scan. Do not drop a multi-movie collection as one folder.

```bash
make jellyfin-library-audit
```

The audit is read-only on `proxmox-applications-1`. It reports folders
without NFO / `tmdbid`, movie folders with more than one feature,
nested `S01.COMPLETE` packs, `*.rar`, and `._*` files. Documentaries
may be a film (`movie.nfo`) or a series (`tvshow.nfo`).

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

## Delete junk next to a title

AppleDouble `._*` and torrent `Samples/` are not features. Same
dataset; delete, do not copy.

```bash
find /mnt/nfs/media/movies /mnt/nfs/media/series \
  /mnt/nfs/media/documentaries /mnt/nfs/media/anime \
  -name '._*' -delete
rm -rf '/mnt/nfs/media/movies/Some.Title/Samples'
```

## Do not

- Mass-rename movie folders that already have `movie.nfo`.
- Run `nix-shell` on this host to pull helper tools.
- `chown` `/mnt/nfs/jellyfin/config`.
