#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$REPO_ROOT/.derivedData}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
GIT_COMMIT="$(git_commit)"

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  GIT_COMMIT="$GIT_COMMIT"

# The optimized Release module still needs testable imports. An ad hoc-signed test
# host must also allow Xcode's test bundle to load; the build above keeps its
# normal hardened-runtime setting.
TEST_BUILD_SETTINGS=(ENABLE_TESTABILITY=YES)
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  TEST_BUILD_SETTINGS+=(ENABLE_HARDENED_RUNTIME=NO)
fi

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  "${TEST_BUILD_SETTINGS[@]}" \
  GIT_COMMIT="$GIT_COMMIT"
