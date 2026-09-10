# Runbook: Radarr / Sonarr pairing and library import

Movies and Shows acquisition lives on `proxmox-applications-1`
([2026-09-09-arr-stack-acquisition](../adr/2026-09-09-arr-stack-acquisition.md)).
Do not add Anime or Documentaries as Sonarr root folders.

## After switch

1. Confirm the units are up:

   ```bash
   ssh root@proxmox-applications-1 \
     systemctl is-active radarr sonarr prowlarr qbittorrent flaresolverr
   ```

2. qBittorrent first-run password is in the journal, not in git:

   ```bash
   ssh root@proxmox-applications-1 \
     journalctl -u qbittorrent -b --no-pager | grep -i password
   ```

   Open `http://proxmox-applications-1:8081`, change the password, set
   Default Save Path to `/mnt/nfs/media/downloads`.

3. In Prowlarr (`:9696`) Settings → Indexers, add FlareSolverr
   (`http://127.0.0.1:8191`). Then add indexers and sync apps to
   Radarr (`:7878`) and Sonarr (`:8989`). Copy API keys from each
   *arr Settings → General. Enable FlareSolverr on indexers that
   return Cloudflare HTML instead of results.

4. In Radarr and Sonarr, add qBittorrent as the download client
   (host `127.0.0.1`, port `8081`). Category `radarr` / `sonarr`.
   Enable completed-download handling and hardlinks (same dataset).

## Import existing Movies

Radarr matches by folder and file name, not the sidecar `tmdbid`.
Most folders are scene-named. Do not bulk-accept.

1. Settings → Media Management → Root Folder
   `/mnt/nfs/media/movies`.
2. Movies → Library Import. Confirm every low-confidence match.
3. Rename in small batches, not one mass action.
4. After each batch:

   ```bash
   make jellyfin-library-audit
   ```

   Spot-check those titles in Jellyfin. Watch progress and trickplay
   on renamed paths may reset. That is accepted.

## Import existing Shows

Same care against `/mnt/nfs/media/series`. Confirm season/episode
mapping before rename batches. Same audit and Jellyfin spot-check.

## Do not

- Point Sonarr at `/mnt/nfs/media/anime` or
  `/mnt/nfs/media/documentaries`.
- "Replace all metadata" in Jellyfin after a rename.
- Put `serverConfig` for qBittorrent in Nix (it would overwrite the
  WebUI password on every switch).
- `chown` `/mnt/nfs/jellyfin/config` or the media dataset to `garage`
  or a guessed uid. If import cannot write, test as the service user
  first; the export may squash to uid 3000.
