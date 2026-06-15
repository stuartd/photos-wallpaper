#!/usr/bin/env bash
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"

if [[ -z "${CI_BUILD_NUMBER:-}" ]]; then
    echo "CI_BUILD_NUMBER is not set; leaving CURRENT_PROJECT_VERSION unchanged."
    exit 0
fi

echo "Setting CURRENT_PROJECT_VERSION to Xcode Cloud build number: $CI_BUILD_NUMBER"
xcrun agvtool new-version -all "$CI_BUILD_NUMBER"
