#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$REPO_ROOT/releases"
APP_PATH="${1:-$RELEASES_DIR/photos-wallpaper.app}"
DMG_PATH="$RELEASES_DIR/photos-wallpaper-alpha-release.dmg"
STAGING="$RELEASES_DIR/photos-wallpaper-dmg-staging-folder"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Usage: $0 /path/to/photos-wallpaper.app"
  exit 1
fi

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING" "$RELEASES_DIR"

ditto "$APP_PATH" "$STAGING/photos-wallpaper.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Photos Wallpaper" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"

rm -rf "$STAGING"
