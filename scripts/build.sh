#!/bin/zsh

GIT_COMMIT="$(git rev-parse --short HEAD)"

xcodebuild clean build -scheme photos-wallpaper -project photos-wallpaper.xcodeproj GIT_COMMIT="$GIT_COMMIT"
xcodebuild test -scheme photos-wallpaper -project photos-wallpaper.xcodeproj -destination 'platform=macOS' GIT_COMMIT="$GIT_COMMIT"
