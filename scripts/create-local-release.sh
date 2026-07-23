#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
    cat <<USAGE
Usage: $0 [-f] [output-directory] [dmg-name]

Build a local release app and DMG, reset first-run state, and open the app.

By default, the reset is refused when the Photos Wallpaper album contains
photos. Pass -f to force the reset and delete the album anyway.
USAGE
}

FORCE_RESET=false
POSITIONAL_ARGS=()
PARSE_OPTIONS=true
while (($# > 0)); do
    if [[ "$PARSE_OPTIONS" == true ]]; then
        case "$1" in
            -f)
                FORCE_RESET=true
                shift
                continue
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                PARSE_OPTIONS=false
                shift
                continue
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 2
                ;;
        esac
    fi

    POSITIONAL_ARGS+=("$1")
    shift
done

if ((${#POSITIONAL_ARGS[@]} > 2)); then
    echo "Too many arguments." >&2
    usage >&2
    exit 2
fi

OUTPUT_DIR="${POSITIONAL_ARGS[0]:-$REPO_ROOT/releases}"
DMG_NAME="${POSITIONAL_ARGS[1]:-Photos Wallpaper.dmg}"
OUTPUT_APP="$OUTPUT_DIR/$APP_BUNDLE_NAME"

echo "Building local Photos Wallpaper app..."
"$SCRIPT_DIR/_create-local.sh" "$OUTPUT_DIR" "$DMG_NAME"

echo
echo "Checking Photos Wallpaper album..."
require_photos_wallpaper_album_reset_permission "$FORCE_RESET"

echo
echo "Resetting first-run state..."
"$SCRIPT_DIR/reset-first-run.sh"

if [[ ! -d "$OUTPUT_APP" ]]; then
    echo "Built app not found: $OUTPUT_APP" >&2
    exit 1
fi

echo
echo "Opening $OUTPUT_APP..."
open "$OUTPUT_APP"
