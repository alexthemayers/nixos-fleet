#!/usr/bin/env bash
# Read-only Jellyfin media-share audit on proxmox-applications-1.
# Usage: ./scripts/jellyfin-library-audit.sh
# Override: HOST=proxmox-applications-1 MEDIA=/mnt/nfs/media
set -euo pipefail

HOST=${HOST:-proxmox-applications-1}
MEDIA=${MEDIA:-/mnt/nfs/media}

ssh -o BatchMode=yes -o ConnectTimeout=15 "root@${HOST}" \
  MEDIA="$MEDIA" bash -s << 'REMOTE'
set -euo pipefail
media=${MEDIA:?}
fail=0

is_feature() {
  local f=$1 base
  base=$(basename "$f")
  shopt -s nocasematch
  case "$base" in
    ._*|*sample*|*trailer*) shopt -u nocasematch; return 1 ;;
  esac
  shopt -u nocasematch
  return 0
}

has_tmdbid() {
  local nfo=$1
  [[ -f "$nfo" ]] && grep -q '<tmdbid>[0-9]\+</tmdbid>' "$nfo"
}

count_features() {
  local dir=$1 n=0 f
  shopt -s nullglob
  for f in "$dir"/*.mkv "$dir"/*.mp4 "$dir"/*.m4v "$dir"/*.avi; do
    [[ -f "$f" ]] || continue
    if is_feature "$f"; then
      n=$((n + 1))
    fi
  done
  shopt -u nullglob
  printf '%s' "$n"
}

echo "=== missing movie.nfo / tmdbid ==="
for d in "$media/movies"/*/; do
  [[ -d "$d" ]] || continue
  if [[ ! -f "${d}movie.nfo" ]]; then
    echo "MISSING nfo  $d"
    fail=1
    continue
  fi
  if ! grep -q '<tmdbid>[0-9]\+</tmdbid>' "${d}movie.nfo"; then
    echo "MISSING tmdbid  $d"
    fail=1
  fi
done

echo "=== missing tvshow.nfo / ids ==="
for d in "$media/series"/*/; do
  [[ -d "$d" ]] || continue
  if [[ ! -f "${d}tvshow.nfo" ]]; then
    echo "MISSING nfo  $d"
    fail=1
    continue
  fi
  if ! has_tmdbid "${d}tvshow.nfo"; then
    echo "MISSING tmdbid  $d"
    fail=1
  fi
done

echo "=== missing documentary sidecar / tmdbid ==="
for d in "$media/documentaries"/*/; do
  [[ -d "$d" ]] || continue
  if [[ -f "${d}tvshow.nfo" ]]; then
    if ! has_tmdbid "${d}tvshow.nfo"; then
      echo "MISSING tmdbid  $d"
      fail=1
    fi
    continue
  fi
  if [[ -f "${d}movie.nfo" ]]; then
    if ! has_tmdbid "${d}movie.nfo"; then
      echo "MISSING tmdbid  $d"
      fail=1
    fi
    continue
  fi
  echo "MISSING nfo  $d"
  fail=1
done

for d in "$media/anime"/*/; do
  [[ -d "$d" ]] || continue
  if [[ ! -f "${d}tvshow.nfo" ]]; then
    echo "MISSING nfo  $d"
    fail=1
    continue
  fi
  if ! grep -q '<tmdbid>[0-9]\+</tmdbid>' "${d}tvshow.nfo"; then
    echo "MISSING tmdbid  $d"
    fail=1
  fi
  if ! grep -q '<anidbid>[0-9]\+</anidbid>' "${d}tvshow.nfo"; then
    echo "MISSING anidbid  $d"
    fail=1
  fi
done

echo "=== movie folders with >1 feature ==="
for d in "$media/movies"/*/; do
  [[ -d "$d" ]] || continue
  n=$(count_features "$d")
  if [[ "$n" -gt 1 ]]; then
    echo "MULTI $n  $d"
    fail=1
  fi
done

echo "=== nested season packs (not Season NN) ==="
for lib in series documentaries anime; do
  for show in "$media/$lib"/*/; do
    [[ -d "$show" ]] || continue
    shopt -s nullglob
    for child in "$show"*/; do
      base=$(basename "$child")
      case "$base" in
        Season\ [0-9][0-9] | Specials | extras | Extras | Samples) continue ;;
      esac
      if [[ "$base" == *COMPLETE* || "$base" == *S[0-9][0-9]* ]]; then
        echo "NESTED  $child"
        fail=1
      fi
    done
    shopt -u nullglob
  done
done

echo "=== rarsets ==="
while IFS= read -r -d '' f; do
  echo "RAR  $f"
  fail=1
done < <(find "$media/movies" "$media/series" "$media/documentaries" "$media/anime" \
  -name '*.rar' -print0 2>/dev/null)

echo "=== AppleDouble ._* ==="
while IFS= read -r -d '' f; do
  echo "APPLEDOUBLE  $f"
  fail=1
done < <(find "$media/movies" "$media/series" "$media/documentaries" "$media/anime" \
  -name '._*' -print0 2>/dev/null)

if [[ "$fail" -eq 0 ]]; then
  echo "OK: library paths look clean"
fi
exit "$fail"
REMOTE
