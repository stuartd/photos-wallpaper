#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

WALLPAPER_PATTERN="current-wallpaper-*.jpg"

date
echo

if [[ ! -d "$APP_SUPPORT_DIR" ]]; then
  echo "No app support directory found at: $APP_SUPPORT_DIR"
  echo
  echo "Macintosh HD free space:"
  df -h /
  exit 0
fi

echo "App support size:"
du -sh "$APP_SUPPORT_DIR"
echo

echo "Files:"
find "$APP_SUPPORT_DIR" -maxdepth 3 -print | sed "s#${APP_SUPPORT_DIR}#.#"
echo

echo "Wallpaper file count:"
WALLPAPER_FILE_COUNT="$(
  find "$APP_SUPPORT_DIR" \
    -name "$WALLPAPER_PATTERN" \
    -type f | wc -l | tr -d ' '
)"
echo "$WALLPAPER_FILE_COUNT"
echo

echo "Wallpaper file total size:"
if [[ "$WALLPAPER_FILE_COUNT" == "0" ]]; then
  echo "0B total"
else
  find "$APP_SUPPORT_DIR" \
    -name "$WALLPAPER_PATTERN" \
    -type f \
    -exec du -ch {} + | tail -1
fi
echo

echo "Macintosh HD free space:"
df -h /
