#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="photos-wallpaper.xcodeproj"
SCHEME="photos-wallpaper"
CONFIGURATION="Release"
APP_NAME="photos-wallpaper.app"
DMG_NAME="photos-wallpaper-alpha-release.dmg"
STAGING="/tmp/photos-wallpaper-dmg"
GIT_COMMIT="$(git rev-parse --short HEAD)"

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  GIT_COMMIT="$GIT_COMMIT"

APP_EXEC_CANDIDATES=()
while IFS= read -r -d '' candidate; do
  APP_EXEC_CANDIDATES+=("$candidate")
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/Build/Products/$CONFIGURATION/$APP_NAME/Contents/MacOS/photos-wallpaper" \
  -not -path "*/Index.noindex/*" \
  -type f \
  -print0)

if [[ ${#APP_EXEC_CANDIDATES[@]} -eq 0 ]]; then
  echo "Could not find built Release app." >&2
  exit 1
fi

APP_EXEC="$(ls -t "${APP_EXEC_CANDIDATES[@]}" | head -1)"
APP="$(dirname "$(dirname "$(dirname "$APP_EXEC")")")"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME"

rm -f "$DMG_NAME"
hdiutil create \
  -volname "Photos Wallpaper" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_NAME"

echo "Built $APP"
echo "Created $DMG_NAME"
