#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_NAME="photos-wallpaper-alpha-release.dmg"

exec "$SCRIPT_DIR/create-release.sh" "$REPO_ROOT/releases" "$DMG_NAME"
