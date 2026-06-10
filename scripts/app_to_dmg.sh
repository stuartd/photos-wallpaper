#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$REPO_ROOT/releases"
APP_PATH="${1:-$RELEASES_DIR/photos-wallpaper.app}"
DMG_PATH="${2:-$RELEASES_DIR/photos-wallpaper.dmg}"
STAGING="$RELEASES_DIR/photos-wallpaper-dmg-staging-folder"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Usage: $0 [/path/to/photos-wallpaper.app] [/path/to/output.dmg]"
  exit 1
fi

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING" "$RELEASES_DIR"
mkdir -p "$(dirname "$DMG_PATH")"

ditto "$APP_PATH" "$STAGING/photos-wallpaper.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Photos Wallpaper" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
