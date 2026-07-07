
### [Photos Wallpaper](https://photos-wallpaper.app)

A native macOS menu bar app that brings back random wallpaper rotation from your Photos library.

Available [on the Mac App Store](https://apps.apple.com/gb/app/photos-wallpaper/id6769191842?mt=12).

Older versions of macOS let you use your Photos library as a rotating wallpaper source and choose a random photo at a fixed interval.[^1]

That functionality is no longer available in macOS 26 Tahoe.[^2] You can have rotate wallpapers from a *folder*, but that is not the same as using the Photos library.

Photos Wallpaper recreates it as a simple menu bar app.

I built this for two reasons: I really missed the feature, and I wanted to see what it would be like to use agentic AI from the product side as a Mac user whose usual background is .NET and Windows apps. Before this project, I had not written any Swift or used Xcode.

The project is also a case study in directing agentic AI to design, implement, test, package, and iterate a real native app to the App Store, with me acting as product owner, QA, release manager, and final decision-maker.

## Featured Project Summary

- **Role:** Product direction, prompt strategy, QA, release management, and final technical decision-making
- **Background:** Built outside my usual .NET/Windows stack, starting with no Swift experience
- **Outcome:** Native macOS app in the App Store
- **Stack:** Swift, SwiftUI, AppKit, Photos.framework, ServiceManagement, UserNotifications, Xcode, GitHub Actions
- **Agentic AI use:** Directed AI agent (Codex) through feature design, implementation, edge-case handling, tests, copy, packaging, and release preparation
- **Evidence of depth:** Unit tests, CI, privacy documentation, release scripts, app metadata, local diagnostics
- **Privacy:** Uses local Photos access only; no accounts, analytics, ads, or server-side storage

## What It Does

- Runs from the macOS menu bar
- Selects random images from the user's Photos library
- Supports multiple displays
- Can change wallpaper immediately
- Supports preset wallpaper schedules
- Can run at login
- Handles wake, unlock, and inactive user-session cases
- Logs local wallpaper history and runtime diagnostics
- Can add the current wallpaper photo or photos to a "Photos Wallpaper" album
- Includes a local privacy document explaining what data is read and written

## Privacy

Photos Wallpaper works locally on the user's Mac.

It does not upload photos, wallpaper history, diagnostics, or usage data. It does not use accounts, analytics, advertising services, or server-side databases.

See [photos-wallpaper/PRIVACY.md](photos-wallpaper/PRIVACY.md) for the full privacy note bundled with the app.

## License

The source code is licensed under the [MIT License](LICENSE).

The Photos Wallpaper name, app icon, screenshots, and other branding assets are not licensed for reuse.

## Agentic AI Case Study

This project demonstrates directing agentic AI through a domain and language I did not know well enough to develop and ship in:

- Translating a project idea into a native macOS product
- Steering implementation across SwiftUI, AppKit, Photos.framework, ServiceManagement, UserNotifications, and macOS wallpaper APIs
- Testing permission flows, multi-display behavior, scheduling, login items, sleep/wake behavior, and local logging
- Iterating based on real use on my own Mac
- Preparing the app for TestFlight, review builds, and the App Store release

The repo includes unit tests, CI, release scripts, privacy copy, app metadata, app icons, local diagnostics, and distribution-oriented build paths.

## Verification

The test suite covers the app's orchestration layer: scheduling, login prompts, Photos authorization states, screen/session behavior, history logging, and album actions.

To build and test locally:

```bash
scripts/build_and_test.sh
```

Or run the Xcode test target directly:

```bash
xcodebuild test \
  -project photos-wallpaper.xcodeproj \
  -scheme photos-wallpaper \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=-
```

To create a release binary:
```bash
scripts/create-local-release.sh 
```

## Notes

This project is intentionally small in product surface area. The goal is to recreate the lost and missed Mac workflow: choose random Photos-library images and keep the desktop wallpaper changing without requiring users to do anything except choose a schedule.

[^1]: [This page](https://www.wallpaperyapp.com/how-to-have-rotating-wallpapers-on-mac) describes the older rotating wallpaper workflow. Archived copies: [Wayback Machine](https://web.archive.org/web/20260509151722/https://www.wallpaperyapp.com/how-to-have-rotating-wallpapers-on-mac), [archive.today](http://archive.today/7snxw).

[^2]: macOS 26 can rotate wallpapers from a _folder_, but that is not the same as using the Photos library directly.
