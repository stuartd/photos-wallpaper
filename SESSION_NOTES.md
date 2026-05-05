# Session Notes

This file captures the practical setup/debugging knowledge from getting `photos-wallpaper` working.

## Current Working State

The app now:

- launches successfully
- runs as a menu bar app
- requests Photos permission correctly
- can pick a photo from the Photos library
- can set the desktop wallpaper
- has a separate test target with controller-focused tests

## Project Layout

The intended project is:

- `photos-wallpaper.xcodeproj`
- app sources under `photos-wallpaper/`
- tests under `photos-wallpaperTests/`

## Important Xcode Configuration

### App Target

Target: `photos-wallpaper`

Important settings:

- uses real plist file:
  - `Generate Info.plist File = No`
  - `Info.plist File = photos-wallpaper/Info.plist`
- menu bar / no Dock icon:
  - `LSUIElement = YES`
- signing for local development:
  - `Signing Certificate = Sign to Run Locally`
- sandbox:
  - currently disabled for local development while the app is being stabilized

Important warning that was fixed:

- `Info.plist` must not appear in `Copy Bundle Resources`

If it is there, Xcode warns:

> The Copy Bundle Resources build phase contains this target's Info.plist file ...

and the target configuration is wrong.

### Test Target

Target: `photos-wallpaperTests`

Important settings:

- should not share the app target's plist
- use generated plist instead:
  - `Generate Info.plist File = Yes`
- do not point `Info.plist File` at `photos-wallpaper/Info.plist`

## Privacy / Photos Permission

The app reads from the Photos library, so the app target must include:

- `NSPhotoLibraryUsageDescription`

This belongs in the built app's `Info.plist`.

The on-disk file is:

- `photos-wallpaper/Info.plist`

The key/value currently used is:

- `NSPhotoLibraryUsageDescription`
- `This app needs to read the photos from your library so it can choose one and set it as your desktop wallpaper.`

Important distinction:

- privacy usage strings belong in `Info.plist`
- entitlements do not replace privacy usage strings

## Why The App Was Crashing Earlier

There were multiple separate issues during setup:

1. The app target was generating its plist instead of using the real plist file.
2. The real plist file existed on disk, but the built app was not using it.
3. A duplicate/nested Xcode project caused confusion about which project and settings were actually active.
4. A backup project folder inside the source tree caused duplicate Swift files to be included in the app target.
5. App Sandbox caused an early launch crash while configuration was in a bad state.

The sandbox crash showed up as a breakpoint in:

- `libsystem_secinit.dylib`

That turned out to be configuration/signing/sandbox setup trouble, not normal app code failure.

## Menu Bar Behavior

The app is intended to be a menu bar utility rather than a normal Dock app.

That is configured through:

- `LSUIElement = YES`

Without that, the app shows a Dock icon.

## How The App Works

High-level runtime flow:

1. `photos_wallpaperApp.swift` starts the app and creates the menu bar UI.
2. `WallpaperCycleController` owns the timer and orchestration logic.
3. `PhotoManager` fetches photos and renders them as `NSImage`.
4. `PhotoManager` writes a temporary JPEG file.
5. `WallpaperManager` asks AppKit / `NSWorkspace` to apply that file as wallpaper.

## Why Temporary Files Are Used

Wallpaper updates are file-based because AppKit's desktop wallpaper API expects a file URL, not raw in-memory image data.

That is why the app:

- loads a `PHAsset`
- requests an `NSImage`
- converts it to JPEG
- writes a temp file
- passes the file URL to `NSWorkspace`

## Testing Setup

There is a separate test target:

- `photos-wallpaperTests`

The tests focus on controller behavior rather than real Photos/AppKit APIs.

The production code was refactored to use protocol boundaries so tests can inject fakes for:

- photo access
- timer scheduling
- notifications
- screens
- defaults persistence
- wallpaper setting

## Running Tests

From the project root:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS'
```

Run only the test target:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' -only-testing:photos-wallpaperTests
```

Run a specific test:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' -only-testing:'photos-wallpaperTests/PhotosWallpaperTests/loadsSavedFrequencyAndSchedulesTimer()'
```

## Building The App

Build from the command line:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' build
```

Release build:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -configuration Release -destination 'platform=macOS' build
```

## Restoring Your Preferred Wallpaper

You asked about restoring your long-term wallpaper after testing.

Simple AppleScript form:

```bash
osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/Users/stuart/Pictures/your-wallpaper-file.jpg"'
```

Replace the path with the real wallpaper file path.

## Distribution Notes

### Local / Informal Testing

For another Mac you can build a Release app bundle and zip it.

Typical flow:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -configuration Release -destination 'platform=macOS' build
```

Then locate the app bundle in DerivedData and zip it with `ditto`.

### Mac App Store

For Mac App Store submission:

- App Sandbox must be enabled
- proper Apple Developer signing/team setup is required
- distribution goes through Xcode archive / Organizer / App Store Connect

Important distinction:

- Mac App Store:
  - sandbox required
  - App Store upload flow
- direct distribution outside the store:
  - Developer ID signing
  - notarization

So the current local-development setup is not yet the final App Store setup.

Before App Store work, revisit:

- App Sandbox
- signing team / certificates
- any capabilities / entitlements required by the final product

## Known Gotchas

- Do not keep backup Xcode projects inside the source tree under `photos-wallpaper/`.
  - the filesystem-synchronized project can recursively include those files
  - that caused duplicate build outputs like `Multiple commands produce ... WallpaperManager.stringsdata`

- Do not point the test target at the app's `Info.plist`.

- If Photos permission crashes reappear, check the built app configuration first:
  - app target must use the real plist
  - built app must contain `NSPhotoLibraryUsageDescription`

- If the Dock icon reappears, check:
  - `LSUIElement = YES`

- If the app dies very early in `libsystem_secinit`, suspect:
  - sandbox/capabilities/signing/configuration
  - not normal app logic

## Files Worth Reading First

If coming back later, start with:

- `README.md`
- `photos-wallpaper/photos_wallpaperApp.swift`
- `photos-wallpaper/WallpaperCycleController.swift`
- `photos-wallpaper/PhotoManager.swift`
- `photos-wallpaper/WallpaperManager.swift`
- `photos-wallpaperTests/photos_wallpaperTests.swift`

## Suggested Next Steps

Reasonable next steps from here:

1. Keep the app stable in the current local-development setup.
2. Run tests regularly from the command line.
3. Add more controller tests before expanding features.
4. When ready for distribution, do a separate App Store hardening pass:
   - re-enable sandbox
   - verify permissions and capabilities
   - archive and test signed builds
