#!/bin/zsh

xcodebuild clean build -scheme photos-wallpaper -project photos-wallpaper.xcodeproj
xcodebuild test -scheme photos-wallpaper -project photos-wallpaper.xcodeproj -destination 'platform=macOS'

