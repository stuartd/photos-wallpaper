#!/usr/bin/env bash

if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "scripts/_common.sh must be sourced from bash." >&2
    return 2 2>/dev/null || exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/photos-wallpaper.xcodeproj"
SCHEME="photos-wallpaper"
VOLUME_NAME="Photos Wallpaper"
APP_BUNDLE_NAME="Photos Wallpaper.app"
XCODE_APP_BUNDLE_NAME="$APP_BUNDLE_NAME"
APP_SUPPORT_DIR="${HOME}/Library/Containers/com.rosehillsolutions.photoswallpaper/Data/Library/Application Support/photos-wallpaper"
PHOTOS_WALLPAPER_ALBUM_NAME="Photos Wallpaper"

KNOWN_DEFAULTS_DOMAINS=(
    "com.rosehillsolutions.photoswallpaper"
)

git_commit() {
    git -C "$REPO_ROOT" rev-parse --short HEAD
}

matching_defaults_domains() {
    printf '%s\n' "${KNOWN_DEFAULTS_DOMAINS[@]}"
}
