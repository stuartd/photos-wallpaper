# Photos Wallpaper Privacy

Photos Wallpaper is a local macOS menu bar app. It uses your Photos library to choose images for your desktop wallpaper and, if you ask it to, it can add the current wallpaper photo(s) to a Photos album, called 'Photos Wallpaper'. All of that work happens on your Mac.

## The Short Version

- Your photos are not uploaded.
- Your wallpaper history is not uploaded.
- There are no accounts, analytics, advertising services, or server-side databases.
- The app reads from your Photos library, asks macOS to set an image as wallpaper, can add selected wallpaper photos to a Photos album, and writes a small amount of local app data.

## Photos Access

Photos Wallpaper asks macOS for permission to read and update your Photos library. That access is needed so the app can pick photo assets, render image data for the wallpaper, and add current wallpaper photos to the Photos Wallpaper album if you choose that menu item.

Photos Wallpaper does not modify, delete, move, tag, favorite, or otherwise edit your photos. The only Photos library change it makes is creating the Photos Wallpaper album if needed and adding selected existing photo assets to that album if you ask it to.

## Photos Wallpaper Album

When you choose "Add Current Wallpaper to Photos Wallpaper Album", Photos Wallpaper looks up the photos it set as wallpaper during the current app session and adds them to an album named "Photos Wallpaper" in your Photos library.

Adding a photo to that album does not duplicate, edit, or move the photo. It only adds the existing Photos asset to the album. If you later remove a photo from that album in Photos, the original photo remains in your library unless you explicitly delete it from Photos.

## Local Settings

The app stores a few settings locally on your Mac:

- the wallpaper refresh frequency you selected
- whether wallpaper selection should prefer wide photos or use all photos
- whether the app should start at login, if you enable that option
- local wallpaper history
- local runtime diagnostics

## Login and Wake Scheduling

To run schedules such as "When I log in" at the right time, Photos Wallpaper reads local macOS session state, including whether this user owns the active console session and the current user's graphical login session identifier. It uses that information only to decide whether a wallpaper cycle should run.

## Wallpaper History

When a wallpaper is applied, Photos Wallpaper writes a plain-text history entry for the current app session. You can view this from the app's Help > Logs menu.

History entries may include:

- the photo filename, when Photos provides one
- the photo creation date, when available
- the Photos asset identifier
- the display name or screen number
- the time the wallpaper was applied

History entries are kept for the current app session and cleared when Photos Wallpaper starts, so the app does not build up a long-term record of wallpaper activity. The history log is kept locally and is not sent anywhere by the app.

## Runtime Diagnostics

Photos Wallpaper also keeps a local diagnostics log to make troubleshooting possible. You can view this from the app's Help > Logs menu.

Diagnostics entries may include:

- wallpaper cycle timing and schedule changes
- Photos permission state and library asset counts
- selected Photos asset identifiers
- generated wallpaper file paths
- success or failure messages from wallpaper updates
- app errors useful for troubleshooting

The diagnostics log is kept locally. It is not sent anywhere by the app.

## Temporary Wallpaper Files

macOS wallpaper APIs work with files, so Photos Wallpaper writes generated wallpaper images into a local app cache before asking macOS to use them as desktop wallpaper. The app marks those generated files as hidden and removes stale generated wallpaper files as it continues running.

## What Never Leaves Your Mac

Photos Wallpaper does not:

- upload your photos
- upload your wallpaper history
- upload your diagnostics log
- create or require an online account
- send your data to a server
- use analytics services
- use advertising services

## Data Flow

The data flow is intentionally simple:

1. Photos Wallpaper reads image data from your Photos library after you grant permission.
2. It creates a local wallpaper image file for the relevant display.
3. It asks macOS to apply that file as desktop wallpaper.
4. If you choose "Add Current Wallpaper to Photos Wallpaper Album", it adds the current wallpaper photo assets to the Photos Wallpaper album.
5. It writes local history and diagnostics entries as described above.

© Stuart Dunkeld 2026
