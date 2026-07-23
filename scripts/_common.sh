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
APP_BUNDLE_ID="com.rosehillsolutions.photoswallpaper"
APP_CONTAINER_PREFERENCES_DOMAIN="${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Library/Preferences/${APP_BUNDLE_ID}"
APP_SUPPORT_DIR="${HOME}/Library/Containers/com.rosehillsolutions.photoswallpaper/Data/Library/Application Support/photos-wallpaper"
PHOTOS_WALLPAPER_ALBUM_NAME="Photos Wallpaper"

KNOWN_DEFAULTS_DOMAINS=(
    "$APP_CONTAINER_PREFERENCES_DOMAIN"
    "$APP_BUNDLE_ID"
)

KNOWN_DEFAULTS_KEYS=(
    "cycleFrequency"
    "didShowMenuBarWelcomeWindow"
    "dismissedStartAtLoginPrompt"
    "dismissedStartAtLoginPromptSchedule"
    "lastHandledLoginSessionIdentifier"
    "nextScheduledCycleDueAt"
    "startAtLoginPromptDeclineCount"
)

git_commit() {
    git -C "$REPO_ROOT" rev-parse --short HEAD
}

matching_defaults_domains() {
    printf '%s\n' "${KNOWN_DEFAULTS_DOMAINS[@]}"
}

quit_running_app_if_needed() {
    local bundle_id="${1:-$APP_BUNDLE_ID}"
    local waited_tenths
    local status

    if ! command -v osascript >/dev/null 2>&1; then
        echo "Could not check for a running app because osascript is unavailable."
        return 0
    fi

    status="$(running_app_status "$bundle_id")"
    if [[ "$status" == "not_running" ]]; then
        echo "No running ${APP_BUNDLE_NAME} process found."
        return 0
    fi

    echo "Quitting running ${APP_BUNDLE_NAME} process..."
    osascript >/dev/null <<APPLESCRIPT
use framework "AppKit"
use scripting additions
set bundleID to "$bundle_id"
set runningApps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:bundleID
repeat with runningApp in runningApps
    runningApp's terminate()
end repeat
APPLESCRIPT

    for waited_tenths in {1..50}; do
        if [[ "$(running_app_status "$bundle_id")" == "not_running" ]]; then
            echo "Running ${APP_BUNDLE_NAME} process quit."
            return 0
        fi
        sleep 0.1
    done

    echo "Could not quit running ${APP_BUNDLE_NAME} process for bundle id: ${bundle_id}" >&2
    return 1
}

running_app_status() {
    local bundle_id="${1:-$APP_BUNDLE_ID}"

    osascript <<APPLESCRIPT
use framework "AppKit"
use scripting additions
set bundleID to "$bundle_id"
set runningApps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:bundleID
if (count of runningApps) is 0 then
    return "not_running"
else
    return "running"
end if
APPLESCRIPT
}

photos_wallpaper_album_item_count() {
    if ! command -v osascript >/dev/null 2>&1; then
        echo "Could not inspect the Photos Wallpaper album because osascript is unavailable." >&2
        return 1
    fi

    osascript <<APPLESCRIPT
tell application "Photos"
    if exists album "${PHOTOS_WALLPAPER_ALBUM_NAME}" then
        return count of media items of album "${PHOTOS_WALLPAPER_ALBUM_NAME}"
    else
        return 0
    end if
end tell
APPLESCRIPT
}

require_photos_wallpaper_album_reset_permission() {
    local force_reset="${1:-false}"
    local item_count

    if ! item_count="$(photos_wallpaper_album_item_count)"; then
        if [[ "$force_reset" == true ]]; then
            echo "Warning: could not inspect the Photos Wallpaper album; proceeding because -f was supplied." >&2
            return 0
        fi

        echo "Refusing to reset first-run state because the Photos Wallpaper album could not be inspected." >&2
        echo "Re-run with -f if deleting the album is intentional." >&2
        return 1
    fi

    if [[ ! "$item_count" =~ ^[0-9]+$ ]]; then
        if [[ "$force_reset" == true ]]; then
            echo "Warning: Photos returned an unexpected album item count; proceeding because -f was supplied." >&2
            return 0
        fi

        echo "Refusing to reset first-run state because Photos returned an unexpected album item count: $item_count" >&2
        echo "Re-run with -f if deleting the album is intentional." >&2
        return 1
    fi

    if ((item_count == 0)); then
        echo "Photos Wallpaper album contains no photos."
        return 0
    fi

    if [[ "$force_reset" == true ]]; then
        echo "Warning: Photos Wallpaper album contains $item_count photo(s); proceeding because -f was supplied." >&2
        return 0
    fi

    echo "Photos Wallpaper album contains $item_count photo(s)." >&2
    echo "Refusing to reset first-run state because that would delete the album." >&2
    echo "Re-run with -f if deleting the album is intentional." >&2
    return 1
}
