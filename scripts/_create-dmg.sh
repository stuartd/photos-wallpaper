#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

APP_PATH="${1:-$REPO_ROOT/releases/$APP_BUNDLE_NAME}"
DMG_PATH="${2:-$REPO_ROOT/releases/Photos Wallpaper.dmg}"
STAGING_DIR="${3:-$REPO_ROOT/releases/photos-wallpaper-dmg-staging}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found: $APP_PATH" >&2
    echo "Usage: $0 [/path/to/Photos Wallpaper.app] [/path/to/output.dmg]" >&2
    exit 1
fi

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
mkdir -p "$(dirname "$DMG_PATH")"

ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created $DMG_PATH"
