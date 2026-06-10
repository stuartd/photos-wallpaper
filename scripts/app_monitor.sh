#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="${HOME}/Library/Application Support/photos-wallpaper"
WALLPAPER_PATTERN="current-wallpaper-*.jpg"

date
echo

echo "App support size:"
if [[ -d "$APP_SUPPORT_DIR" ]]; then
  du -sh "$APP_SUPPORT_DIR"
else
  echo "No app support directory found at: $APP_SUPPORT_DIR"
fi
echo

echo "Files:"
if [[ -d "$APP_SUPPORT_DIR" ]]; then
  ls -lh "$APP_SUPPORT_DIR"
else
  echo "No files to show."
fi
echo

echo "Wallpaper file count:"
if [[ -d "$APP_SUPPORT_DIR" ]]; then
  find "$APP_SUPPORT_DIR" \
    -name "$WALLPAPER_PATTERN" \
    -type f | wc -l
else
  echo 0
fi
echo

echo "Wallpaper file total size:"
if [[ -d "$APP_SUPPORT_DIR" ]]; then
  find "$APP_SUPPORT_DIR" \
    -name "$WALLPAPER_PATTERN" \
    -type f \
    -exec du -ch {} + | tail -1
else
  echo "0B total"
fi
echo

echo "Macintosh HD free space:"
df -h /
