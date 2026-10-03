
## [Photos Wallpaper](https://photos-wallpaper.app)

### A free native macOS menu bar app that brings back random wallpaper rotation from your Photos library to your desktop.

### [Get it from the Mac App Store](https://apps.apple.com/gb/app/photos-wallpaper/id6769191842?mt=12)

---
### Why?

macOS used to have a feature that let you use your Photos library as a rotating wallpaper source, and it would choose a random photo and set it as the wallpaper at a chosen interval.[^1] 

The feature was removed in macOS 26 (Sequoia).[^2]

**I really liked that feature and I missed it, so I recreated it with Photos Wallpaper!**

---
### What it does

- Runs from the macOS menu bar
- Selects random images from your Photos library and sets them as wallpaper
- Supports multiple displays
- You can change your wallpaper on demand, or use a preset wallpaper schedule
- Change wallpaper from any app with Control–Option–W. Choose **Change Keyboard Shortcut…** in the menu to set your own shortcut or restore the default.
- You can add the current wallpaper photo to a "Photos Wallpaper" album in Photos, and then use that so see the photo in context in your library.

---
### Privacy

Photos Wallpaper works locally on your Mac.

It does not upload your photos, wallpaper history, diagnostics, or usage data. It does not use accounts, analytics, cloud services, or any form of advertising.

See [photos-wallpaper/PRIVACY.md](photos-wallpaper/PRIVACY.md) for the full privacy notes.

---
### Scripting

The 'add to photos wallpaper album' action can be automated: the command requires Photos Wallpaper to have set the photo during the current app session. 

```applescript
tell application "Photos Wallpaper"
    add current wallpaper to photos wallpaper album
end tell
```

Or
```osascript
osascript -e 'tell application "Photos Wallpaper" to add current wallpaper to photos wallpaper album'
```

You can open the album using this script:

```applescript
tell application "Photos"
	reopen
	activate
	if exists album "Photos Wallpaper" then
		spotlight album "Photos Wallpaper"
	else
		display dialog "No Photos Wallpaper album found." buttons {"OK"} default button "OK"
	end if
end tell
```

---
### License

The source code is licensed under the [MIT License](LICENSE).

The Photos Wallpaper name, app icon, screenshots, and other branding assets are not licensed for reuse.

---
### Verification

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

This local release smoke test resets first-run state before opening the app. It
refuses to continue if the Photos Wallpaper album contains photos. Pass `-f`
only when deleting that album is intentional:

```bash
scripts/create-local-release.sh -f
```

---
### Notes

[^1]: [This page](https://www.wallpaperyapp.com/how-to-have-rotating-wallpapers-on-mac) describes the older rotating wallpaper workflow. Archived copies: [Wayback Machine](https://web.archive.org/web/20260509151722/https://www.wallpaperyapp.com/how-to-have-rotating-wallpapers-on-mac), [archive.today](http://archive.today/7snxw).

[^2]: macOS 26 can rotate wallpapers from a _folder_, but that is not the same as using the Photos library directly.
