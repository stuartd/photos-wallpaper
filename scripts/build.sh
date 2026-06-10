#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/photos-wallpaper.xcodeproj"
SCHEME="photos-wallpaper"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$REPO_ROOT/.derivedData}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  GIT_COMMIT="$GIT_COMMIT"

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  GIT_COMMIT="$GIT_COMMIT"
