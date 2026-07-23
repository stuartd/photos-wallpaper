# Agent Guide

## Project Context

Photos Wallpaper is a native macOS menu bar app that restores random wallpaper rotation from the user's Photos library. It is intentionally small in product surface area and privacy-sensitive: work happens locally on the Mac, with no accounts, analytics, ads, or server-side storage.

The user is product owner, QA, release manager, and final decision-maker. Prefer changes that preserve the app's simple workflow: choose a schedule, let the app pick Photos-library images, and keep desktop wallpapers changing with as little user effort as possible.

## Repository Map

- `photos-wallpaper/`: app source.
- `photos-wallpaper/photos_wallpaperApp.swift`: SwiftUI entry point and menu bar commands.
- `photos-wallpaper/WallpaperCycleController.swift`: scheduling, wake/unlock/session handling, screen coordination, and notification behavior.
- `photos-wallpaper/PhotoManager.swift`: Photos.framework access, random asset selection, image rendering, album updates, and wallpaper application bridge.
- `photos-wallpaper/WallpaperManager.swift`: AppKit wallpaper API wrapper.
- `photos-wallpaper/LoginItemManager.swift`: start-at-login integration and prompting.
- `photos-wallpaper/WallpaperHistoryLogger.swift`: runtime diagnostics, history formatting, bounded log files, and log windows.
- `photos-wallpaper/CurrentWallpaperAlbumController.swift`: "Add Current Wallpaper(s) to Photos Wallpaper Album" flow.
- `photos-wallpaper/FirstRunNotifier.swift`: first-run welcome behavior.
- `photos-wallpaper/PRIVACY.md`: user-facing privacy copy bundled with the app.
- `photos-wallpaperTests/`: Swift Testing tests focused on orchestration and formatting.
- `scripts/`: local build, release, diagnostics, reset, and Photos album helper scripts.
- `ci_scripts/`: CI bootstrap scripts.

## Build And Test

Use the project script for local verification:

```bash
scripts/build_and_test.sh
```

Equivalent direct test command:

```bash
xcodebuild test \
  -project photos-wallpaper.xcodeproj \
  -scheme photos-wallpaper \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=-
```

The build script sets `DERIVED_DATA_DIR` to `.derivedData` by default and passes the current git commit into the build. Release packaging goes through:

```bash
scripts/create-local-release.sh
```

## Scripts Folder

- `scripts/build_and_test.sh`: primary local verification path. Builds and tests the Xcode project.
- `scripts/show-saved-data.sh`: read-only diagnostics for saved defaults, app support files, history log, runtime log, Photos permission guidance, and login-item guidance.
- `scripts/app_monitor.sh`: read-only app support and generated wallpaper cache size check.
- `scripts/reset-first-run.sh`: state-reset helper. It deletes matching defaults, local app support logs/cache/history, the Photos Wallpaper album, and Photos permission state. Run only when a reset is intentional.
- `scripts/create-local-release.sh`: local release smoke-test helper. It builds a local app/DMG, checks that the Photos Wallpaper album is empty, resets first-run state, and opens the built app. It refuses to delete an album containing photos unless `-f` is passed.
- `scripts/expire-testflight-builds.sh`: App Store Connect maintenance helper. It is dry-run by default, needs App Store Connect API credentials, and only expires builds when `--apply` is passed.
- `scripts/_common.sh`: shared script constants and helpers. Keep bundle IDs, app support paths, app names, and album names aligned with app behavior.
- `scripts/_create-local.sh`, `scripts/_create-dmg.sh`, and `scripts/_delete-photos-wallpaper-album.sh`: private helpers used by public scripts. Prefer invoking the public scripts unless working on the helper itself.

## Coding Guidelines

- Keep the app native: Swift, SwiftUI, AppKit, Photos.framework, ServiceManagement, UserNotifications, and Foundation.
- Keep app behavior local-first and privacy-preserving. Do not introduce network calls, analytics, external storage, or telemetry without explicit user direction.
- Maintain the small menu bar app surface. Avoid adding new windows, flows, preferences, or onboarding unless they directly support the core wallpaper workflow.
- Favor dependency-injected protocols around system APIs so behavior stays testable without touching Photos, AppKit, ServiceManagement, timers, notifications, or real displays.
- Preserve `@MainActor` boundaries for UI, AppKit, and controller state. Be careful when adding async callbacks from Photos or notification APIs.
- Use `debugLog(...)` for operational diagnostics rather than raw `print`, except for debug-only local experiments.
- Keep user-facing text plain, specific, and consistent with the existing menu copy.
- Ideally do not change privacy-relevant behaviour at all. If it is necessary and has been approved, update `photos-wallpaper/PRIVACY.md` in the same change.
- Keep comments useful for Swift/macOS context. Existing comments intentionally explain Apple-framework concepts for readers who may not know Swift or Xcode well.

## Testing Expectations

- Use Swift Testing (`import Testing`, `@Test`, `#expect`) for new tests, matching the existing suite.
- The main test suite is `@MainActor`. Keep controller and UI-adjacent tests on the main actor so AppKit values, `@Published` controller state, and `@MainActor` production types are accessed consistently.
- When production code schedules work with `Task { @MainActor in ... }`, callbacks, or dispatch queues, let tests observe that work with `await Task.yield()`, `waitForCondition`, or fake-specific wait helpers.
- Drive time and system events through fakes: `FakeTimerScheduler`, fake wake/session observers, fake screen/session providers, fake defaults, fake Photos managers, and fake notifiers. Fire fake timers and event handlers directly instead of waiting for real time.
- Add or update tests in `photos-wallpaperTests/photos_wallpaperTests.swift` for controller logic, schedule behavior, prompts, state persistence, log formatting, and album/history workflows.
- Use fakes, not mocks, for tests in this project.
- Prefer fakes and injected collaborators over tests that require a real Photos library, real wallpaper changes, login item mutation, or notification permission prompts.
- If a test needs an `NSScreen`, it can use one host `NSScreen` as a screen-shaped value, but behavior should still be driven through `FakeScreenProvider`.
- For changes touching real macOS integration points, cover the decision logic with tests and keep the system API call behind a small wrapper.
- Run `scripts/build_and_test.sh` when feasible before handing work back.

## Product And Privacy Boundaries

- The app reads Photos assets only after macOS permission allows it.
- The app may create and update a Photos album named "Photos Wallpaper" only when the user chooses the album action.
- Wallpaper history and runtime diagnostics are local plain-text logs.
- Generated wallpaper files are local cache files used because macOS wallpaper APIs need file URLs.
- Do not add behavior that edits, deletes, moves, uploads, favorites, tags, or otherwise modifies user photos.

## Release Notes For Agents

- Avoid unrelated Xcode project churn. Only edit `photos-wallpaper.xcodeproj/project.pbxproj` when adding or removing project files that Xcode must compile or bundle.
- Root documentation files such as this one do not need to be added to the Xcode project.
- Scripts use bash with `set -euo pipefail`; keep script changes compatible with the shared helpers in `scripts/_common.sh`.
- The app bundle identifier and local container paths are defined in the Xcode project and `scripts/_common.sh`; keep scripts and app behavior aligned if those ever change.
