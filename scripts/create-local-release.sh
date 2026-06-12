#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

OUTPUT_DIR="${1:-$REPO_ROOT/releases}"
DMG_NAME="${2:-Photos Wallpaper.dmg}"
OUTPUT_APP="$OUTPUT_DIR/$APP_BUNDLE_NAME"

echo "Building local Photos Wallpaper app..."
"$SCRIPT_DIR/create-local.sh" "$OUTPUT_DIR" "$DMG_NAME"

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
