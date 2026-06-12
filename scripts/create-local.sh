# For local testing only. This builds a locally signed app/DMG and is not the App Store release path.

#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CONFIGURATION="Release"
DMG_NAME="${2:-Photos Wallpaper.dmg}"

OUTPUT_DIR="${1:-$REPO_ROOT/releases}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/photos-wallpaper-release-derived-data.XXXXXX")"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
BUILT_APP="$BUILD_PRODUCTS_DIR/$XCODE_APP_BUNDLE_NAME"
OUTPUT_APP="$OUTPUT_DIR/$APP_BUNDLE_NAME"
if [[ "$DMG_NAME" = /* ]]; then
    OUTPUT_DMG="$DMG_NAME"
else
    OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"
fi

GIT_COMMIT="$(git_commit)"

cleanup() {
    rm -rf "$DERIVED_DATA_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$OUTPUT_DMG")"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild clean build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
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
"$SCRIPT_DIR/create-dmg.sh" "$OUTPUT_APP" "$OUTPUT_DMG" "$OUTPUT_DIR/photos-wallpaper-dmg-staging"

echo
echo "Release artifacts:"
echo "App: $OUTPUT_APP"
echo "DMG: $OUTPUT_DMG"
