# photos-wallpaper Overview

Small macOS menu bar app that picks photos from your Photos library and sets them as desktop wallpaper.

## Current State

The app currently:

- launches successfully
- runs as a menu bar app
- requests Photos permission correctly
- sets wallpaper successfully
- keeps a plain-text wallpaper history log
- has a separate test target with controller-focused tests

## Project Layout

The intended project is:

- `photos-wallpaper.xcodeproj`
- app sources under `photos-wallpaper/`
- tests under `photos-wallpaperTests/`

Important: the correct Xcode project to keep is the root `photos-wallpaper.xcodeproj`.

## Main Files

- `photos-wallpaper/photos_wallpaperApp.swift`
  - SwiftUI app entry point and menu bar UI

- `photos-wallpaper/WallpaperCycleController.swift`
  - orchestration layer
  - owns the timer, frequency, screen/photo coordination, and notification behavior

- `photos-wallpaper/PhotoManager.swift`
  - Photos.framework bridge
  - fetches assets, requests rendered images, formats history labels, and hands images off for wallpaper application

- `photos-wallpaper/WallpaperManager.swift`
  - thin wrapper over `NSWorkspace` wallpaper APIs

- `photos-wallpaper/WallpaperHistoryLogger.swift`
  - appends wallpaper history to a plain-text log and can open the log from the menu

- `photos-wallpaperTests/photos_wallpaperTests.swift`
  - controller-level tests using fakes instead of real system APIs

## High-Level Flow

At runtime:

1. `photos_wallpaperApp.swift` starts the app and creates the menu bar menu.
2. `WallpaperCycleController` owns the selected frequency and repeating timer.
3. Each cycle, the controller asks for the current screens and random photo assets.
4. `PhotoManager` asks Photos to render images for those assets.
5. `PhotoManager` converts the images to temporary JPEG files.
6. `WallpaperManager` asks AppKit to apply those files as wallpaper.
7. `WallpaperHistoryLogger` records what was shown.

## Architecture Notes

The controller depends on protocols rather than directly on system APIs.

That separation exists so:

- app logic is easier to reason about
- Photos/AppKit behavior is isolated
- tests can inject fakes for timers, screens, notifications, persistence, and wallpaper writes

In short: the code that makes decisions is testable without touching the real Photos library or the real desktop wallpaper.

## Important Xcode Configuration

### App Target: `photos-wallpaper`

Important settings:

- uses a real plist file:
  - `Generate Info.plist File = No`
  - `Info.plist File = photos-wallpaper/Info.plist`
- menu bar / no Dock icon:
  - `LSUIElement = YES`
- local signing:
  - `Signing Certificate = Sign to Run Locally`
- sandbox:
  - currently disabled for local development while the app is being stabilized

Also:

- `Info.plist` must not appear in `Copy Bundle Resources`

### Test Target: `photos-wallpaperTests`

Important settings:

- should not share the app plist
- use generated plist instead:
  - `Generate Info.plist File = Yes`

## Privacy / Photos

The app reads from the Photos library, so the built app must contain:

- `NSPhotoLibraryUsageDescription`

That lives in:

- `photos-wallpaper/Info.plist`

Current string:

- `This app needs to read the photos from your library so it can choose one and set it as your desktop wallpaper.`

Privacy usage strings belong in `Info.plist`, not entitlements.

## Wallpaper History

The app now keeps a plain-text history log at:

- `~/Library/Application Support/photos-wallpaper/wallpaper-history.log`

Entries include:

- original filename when available
- creation date when available
- Photos `localIdentifier` as a precise fallback
- monitor number
- timestamp when the wallpaper was applied

There is also a menu item:

- `Show wallpaper history`

## Running The App

From Xcode:

- open `photos-wallpaper.xcodeproj`
- run the `photos-wallpaper` scheme

From the command line:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' build
```

## Running Tests

Run all tests:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS'
```

Run only the test target:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' -only-testing:photos-wallpaperTests
```

Run one specific test:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' -only-testing:'photos-wallpaperTests/PhotosWallpaperTests/loadsSavedFrequencyAndSchedulesTimer()'
```

## Practical Notes

- wallpaper updates are file-based because AppKit expects a file URL, not in-memory image data
- the Photos fetch is refreshed so new photos and permission changes are picked up without restarting
- duplicate filenames in Photos are handled in history output by including creation date and identifier
- some Photos metadata lookups may warn about on-demand fetching on the main queue; that is a performance smell, not currently a correctness bug

## Distribution Notes

### Local Testing

For another Mac, a Release build can be created with:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -configuration Release -destination 'platform=macOS' build
```

### Mac App Store

For App Store submission later:

- App Sandbox must be enabled
- proper Apple Developer signing/team setup is required
- distribution goes through Xcode archive / Organizer / App Store Connect

Current local-development settings are intentionally simpler than the eventual App Store setup.

## Known Gotchas

- do not keep backup Xcode projects inside `photos-wallpaper/`
- do not point the test target at the app target's `Info.plist`
- if Photos permission issues reappear, first confirm the app target is using the real plist file
- if the Dock icon reappears, check `LSUIElement = YES`
- if the app dies very early in `libsystem_secinit`, suspect sandbox/signing/configuration before suspecting app logic
