#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This will delete the \"${PHOTOS_WALLPAPER_ALBUM_NAME}\" album from Photos."
  echo "It does not delete the photos inside the album."
  echo
  echo "Usage: $0 --yes"
  exit 2
fi

osascript <<APPLESCRIPT
tell application "Photos"
    if exists album "${PHOTOS_WALLPAPER_ALBUM_NAME}" then
        delete album "${PHOTOS_WALLPAPER_ALBUM_NAME}"
        return "Deleted ${PHOTOS_WALLPAPER_ALBUM_NAME} album."
    else
        return "No ${PHOTOS_WALLPAPER_ALBUM_NAME} album found."
    end if
end tell
APPLESCRIPT
