#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/photos-wallpaper.xcodeproj"
SCHEME="photos-wallpaper"
CONFIGURATION="Release"
APP_NAME="photos-wallpaper.app"
DMG_NAME="photos-wallpaper.dmg"
VOLUME_NAME="Photos Wallpaper"

OUTPUT_DIR="${1:-$REPO_ROOT/releases}"
DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/photos-wallpaper-release-derived-data.XXXXXX")"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
BUILT_APP="$BUILD_PRODUCTS_DIR/$APP_NAME"
OUTPUT_APP="$OUTPUT_DIR/$APP_NAME"
OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$OUTPUT_DIR/photos-wallpaper-dmg-staging"

GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

cleanup() {
  rm -rf "$DERIVED_DATA_DIR" "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  GIT_COMMIT="$GIT_COMMIT"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

echo
echo "Copying app to $OUTPUT_APP..."
rm -rf "$OUTPUT_APP"
ditto "$BUILT_APP" "$OUTPUT_APP"

echo
echo "Creating DMG at $OUTPUT_DMG..."
rm -rf "$STAGING_DIR" "$OUTPUT_DMG"
mkdir -p "$STAGING_DIR"
ditto "$OUTPUT_APP" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

rm -rf "$STAGING_DIR"

echo
echo "Release artifacts:"
echo "App: $OUTPUT_APP"
echo "DMG: $OUTPUT_DMG"
