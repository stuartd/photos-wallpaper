# photos-wallpaper

Small macOS menu bar app that picks photos from your Photos library and sets them as desktop wallpaper.

## What It Does

At runtime the app does four things:

1. Starts as a menu bar app.
2. Remembers how often you want the wallpaper to change.
3. Picks one photo per screen from the Photos library.
4. Renders those photos to temporary JPEG files and asks macOS to apply them as wallpaper.

## High-Level Flow

The code is split into a few focused pieces:

- `photos-wallpaper/photos_wallpaperApp.swift`
  - SwiftUI entry point.
  - Creates the menu bar UI and owns the long-lived controller.

- `photos-wallpaper/WallpaperCycleController.swift`
  - Orchestrates the app.
  - Owns the timer, remembers the selected cycle frequency, asks for screens, requests photos, and coordinates wallpaper updates.

- `photos-wallpaper/PhotoManager.swift`
  - Talks to Photos.framework and image conversion APIs.
  - Fetches `PHAsset` records, requests rendered `NSImage` instances, converts them to JPEG, and passes the file to the wallpaper layer.

- `photos-wallpaper/WallpaperManager.swift`
  - Thin wrapper around AppKit's wallpaper API.
  - Takes a file URL and applies it to one or more screens using `NSWorkspace`.

- `photos-wallpaperTests/photos_wallpaperTests.swift`
  - Controller-level tests.
  - Uses fake collaborators instead of real Photos/AppKit calls.

## Why The Architecture Looks Like This

The controller depends on protocols rather than concrete system APIs.

That buys two things:

- clearer boundaries between "app logic" and "Apple framework glue"
- unit tests that can verify behavior without reading the real Photos library, setting the real wallpaper, or waiting on real timers

In other words, the app is structured so the code that makes decisions can be tested separately from the code that touches macOS.

## Swift / Apple Concepts Used Here

If you are experienced in other languages, these are the main Swift-specific ideas worth knowing:

- `protocol`
  - Interface/contract.
  - Similar to an interface in Java/C# or a trait-like dependency boundary used for mocking.

- `@MainActor`
  - Means the type or function should run on the main UI actor/thread.
  - Important when touching AppKit or UI-bound state.

- `@Published`
  - Property wrapper that lets SwiftUI observe changes automatically.

- `@StateObject`
  - Tells SwiftUI to create and retain a reference-type object for the lifetime of the view/app.

- closure
  - Swift's function literal.
  - Used heavily for callbacks, especially in Apple APIs.

- escaping closure
  - A closure that may be called after the current function returns.
  - Common in async callback-based APIs such as Photos image requests.

- `Task`
  - Starts asynchronous work.
  - Here it is mainly used to move work back onto the main actor safely.

- `PHAsset`
  - A Photos library record/handle, not the image bytes themselves.

- `NSImage`
  - AppKit image type on macOS.

- `NSScreen`
  - AppKit representation of a connected display.

- `NSWorkspace`
  - AppKit system integration API that includes wallpaper-setting support.

## Privacy / App Configuration

This app reads from the Photos library, so the app target must provide a valid `NSPhotoLibraryUsageDescription` in its built `Info.plist`.

This repo is configured to use:

- app target:
  - real plist file at `photos-wallpaper/Info.plist`
- test target:
  - generated plist

The app is also configured as a menu bar agent app via `LSUIElement`, which hides the Dock icon.

## Running The App

From Xcode:

- open `photos-wallpaper.xcodeproj`
- build and run the `photos-wallpaper` scheme

From the command line:

```bash
xcodebuild -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' build
```

## Running Tests

Run the full test target:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS'
```

Run only the app test target:

```bash
xcodebuild test -project photos-wallpaper.xcodeproj -scheme photos-wallpaper -destination 'platform=macOS' -only-testing:photos-wallpaperTests
```

## Practical Notes

- Wallpaper updates are file-based because AppKit expects a file URL, not an in-memory image.
- The app refreshes the Photos fetch periodically so new photos and permission changes are seen without restarting.
- Tests focus on controller behavior rather than trying to test Apple's frameworks themselves.
