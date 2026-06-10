#!/usr/bin/env bash
set -euo pipefail

ALBUM_NAME="Photos Wallpaper"

if [[ "${1:-}" != "--yes" ]]; then
  echo "This will delete the \"${ALBUM_NAME}\" album from Photos."
  echo "It does not delete the photos inside the album."
  echo
  echo "Usage: $0 --yes"
  exit 2
fi

osascript <<APPLESCRIPT
tell application "Photos"
    if exists album "${ALBUM_NAME}" then
        delete album "${ALBUM_NAME}"
        return "Deleted ${ALBUM_NAME} album."
    else
        return "No ${ALBUM_NAME} album found."
    end if
end tell
APPLESCRIPT
