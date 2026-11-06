# Runbook: Radarr / Sonarr pairing and library import

Movies and Shows acquisition lives on `proxmox-applications-debian`
([2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md)).
Do not add Anime or Documentaries as Sonarr root folders.

## After switch

1. Confirm the units are up:

   ```bash
   ssh root@proxmox-applications-debian \
     systemctl is-active radarr sonarr prowlarr qbittorrent flaresolverr bazarr
   ```

2. qBittorrent first-run password is in the journal, not in git.
   The live WebUI password stays in
   `/var/lib/qBittorrent/.../qBittorrent.conf`. Tailnet login still
   needs it. `*arr` on the same VM talk to `127.0.0.1:8081` with
   `WebUI\LocalHostAuth=false` (localhost only). Do not put
   `serverConfig` in Nix or a switch will wipe both the password and
   that bypass. Default Save Path is
   `/mnt/nfs/media/downloads`.

3. Prowlarr (`:9696`) already has FlareSolverr
   (`http://127.0.0.1:8191/`, timeout 90s, tag `cloudflare`) and
   full-sync apps for Radarr (`127.0.0.1:7878`) and Sonarr
   (`127.0.0.1:8989`). On each new Cloudflare indexer set the
   `cloudflare` tag / Indexer Proxy **before** Test. A Test with the
   proxy left at None hits the site directly and still reports
   `blocked by CloudFlare Protection`. Then Settings → Apps →
   Sync App Indexers.

4. qBittorrent is already the download client on Prowlarr, Radarr,
   and Sonarr (`127.0.0.1:8081`, categories `prowlarr` / `radarr` /
   `sonarr`). Completed-download handling and hardlinks are on.
   Roots are `/mnt/nfs/media/movies` and `/mnt/nfs/media/series`.
   Rename is on for new grabs. Do not add anime or documentary
   roots.

5. Radarr and Sonarr Connect already have `Jellyfin` at
   `127.0.0.1:8096` (library update on import / upgrade / rename /
   delete). Kodi/XBMC metadata is on and writes `movie.nfo` /
   `tvshow.nfo`. Settings → Connect → Test if a refresh stops
   landing.

6. Bazarr (`:6767`) is paired to Radarr and Sonarr on `127.0.0.1`,
   and to Jellyfin at `127.0.0.1:8096` so a new `.srt` refreshes
   the library. It ignores PGS when deciding a title already has
   subs. The default language profile is English. Add a subtitle
   provider in the UI (OpenSubtitles.com or similar); until then it
   will sync and find nothing. After a provider exists, run a wanted
   search from the Movies/Series views. Do not point it at anime or
   documentaries.

## Import existing Movies

Radarr matches by folder and file name, not the sidecar `tmdbid`.
Most folders are scene-named. Do not bulk-accept.

1. Root folder `/mnt/nfs/media/movies` is already there. Movies →
   Library Import. Confirm every low-confidence match.
2. Rename in small batches, not one mass action.
3. After each batch:

   ```bash
   make jellyfin-library-audit
   ```

   Spot-check those titles in Jellyfin. Watch progress and trickplay
   on renamed paths may reset. That is accepted.

## Import existing Shows

Same care against `/mnt/nfs/media/series` (root already added).
Confirm season/episode mapping before rename batches. Same audit
and Jellyfin spot-check.

## Do not

- Point Sonarr or Bazarr at `/mnt/nfs/media/anime` or
  `/mnt/nfs/media/documentaries`.
- "Replace all metadata" in Jellyfin after a rename.
- Put `serverConfig` for qBittorrent in Nix (it would overwrite the
  WebUI password and `LocalHostAuth` bypass on every switch).
- `chown` `/mnt/nfs/jellyfin/config` or the media dataset to `garage`
  or a guessed uid. If import cannot write, test as the service user
  first; the export may squash to uid 3000.
