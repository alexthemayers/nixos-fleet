#!/bin/bash
# Copy the repo's Jellyfin config over the NFS copies. The files are writable
# because Jellyfin rewrites encoding.xml on start. A dashboard edit to one of
# these files does not survive the next start.
set -euo pipefail
src=/usr/local/share/jellyfin-managed
live=/run/jellyfin/live
caddy=$(getent ahostsv4 xcloud-caddy | awk '{print $1; exit}')
if [ -z "${caddy}" ]; then
  echo "jellyfin-render-config: xcloud-caddy did not resolve" >&2
  exit 1
fi
# Paths under live/ mirror the official container's /config layout.
# Owner is jellyfin (uid 3003); media libraries stay readable via group 3000.
uid=3003
gid=3003
rm -rf "${live}"
install -d -o "${uid}" -g "${gid}" "${live}"
while read -r rel dest; do
  [ -n "${rel}" ] || continue
  install -d -o "${uid}" -g "${gid}" "$(dirname "${live}${dest}")"
  cp "${src}/${rel}" "${live}${dest}"
  chown "${uid}:${gid}" "${live}${dest}"
  chmod 0644 "${live}${dest}"
done <<'EOF'
config/system.xml /config/config/system.xml
config/encoding.xml /config/config/encoding.xml
config/branding.xml /config/config/branding.xml
config/database.xml /config/config/database.xml
config/xbmcmetadata.xml /config/config/xbmcmetadata.xml
config/logging.json /config/config/logging.json
plugins/Jellyfin.Plugin.AniDB.xml /config/plugins/configurations/Jellyfin.Plugin.AniDB.xml
plugins/Jellyfin.Plugin.MusicBrainz.xml /config/plugins/configurations/Jellyfin.Plugin.MusicBrainz.xml
plugins/Jellyfin.Plugin.Omdb.xml /config/plugins/configurations/Jellyfin.Plugin.Omdb.xml
plugins/Jellyfin.Plugin.StudioImages.xml /config/plugins/configurations/Jellyfin.Plugin.StudioImages.xml
plugins/Jellyfin.Plugin.Tmdb.xml /config/plugins/configurations/Jellyfin.Plugin.Tmdb.xml
libraries/Anime/options.xml /config/root/default/Anime/options.xml
libraries/Anime/anime.mblink /config/root/default/Anime/anime.mblink
libraries/Movies/options.xml /config/root/default/Movies/options.xml
libraries/Movies/movies.mblink /config/root/default/Movies/movies.mblink
libraries/Documentaries/options.xml /config/root/default/Documentaries/options.xml
libraries/Documentaries/documentaries.mblink /config/root/default/Documentaries/documentaries.mblink
libraries/Music/options.xml /config/root/default/Music/options.xml
libraries/Music/music.mblink /config/root/default/Music/music.mblink
libraries/Shows/options.xml /config/root/default/Shows/options.xml
libraries/Shows/series.mblink /config/root/default/Shows/series.mblink
EOF
install -d -o "${uid}" -g "${gid}" \
  "${live}/config/config" \
  "${live}/config/plugins/configurations"
sed "s/__PROXY_XCLOUD_CADDY__/${caddy}/" \
  "${src}/config/network.xml" >"${live}/config/config/network.xml"
python3 - <<'PY'
from pathlib import Path
src = Path("/usr/local/share/jellyfin-managed/plugins/SSO-Auth.xml")
dest = Path("/run/jellyfin/live/config/plugins/configurations/SSO-Auth.xml")
secret = Path("/etc/jellyfin/oid-secret").read_text().strip()
dest.write_text(src.read_text().replace("@OID_SECRET@", secret))
PY
chown "${uid}:${gid}" \
  "${live}/config/config/network.xml" \
  "${live}/config/plugins/configurations/SSO-Auth.xml"
chmod 0644 "${live}/config/config/network.xml"
chmod 0440 "${live}/config/plugins/configurations/SSO-Auth.xml"
