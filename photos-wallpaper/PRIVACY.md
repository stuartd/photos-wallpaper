# Photos Wallpaper Privacy

Photos Wallpaper is a local macOS menu bar app. It uses your Photos library only to choose images for your desktop wallpaper, and all of that work happens on your Mac.

## The Short Version

- Your photos are not uploaded.
- Your wallpaper history is not uploaded.
- There are no accounts, analytics, advertising services, or server-side databases.
- The app reads from your Photos library, asks macOS to set wallpaper, and writes a small amount of local app data.

## Photos Access

Photos Wallpaper asks macOS for permission to read your Photos library. That access is needed so the app can pick photo assets and render image data for wallpaper-sized previews.

The app does not modify, delete, move, tag, favorite, or otherwise change anything in your Photos library.

## Local Settings

The app stores a few settings locally on your Mac:

- the wallpaper refresh frequency you selected
- whether the app should start at login, if you enable that option
- local wallpaper history
- local runtime diagnostics

## Wallpaper History

When a wallpaper is applied, Photos Wallpaper can write a plain-text history entry for the current app session.

The history file is stored here:

`~/Library/Application Support/photos-wallpaper/wallpaper-history.log`

History entries may include:

- the photo filename, when Photos provides one
- the photo creation date, when available
- the Photos asset identifier
- the display name or screen number
- the time the wallpaper was applied

The history log is cleared when Photos Wallpaper starts. It is kept locally and is not sent anywhere by the app.

## Runtime Diagnostics

Photos Wallpaper also keeps a local diagnostics log to make troubleshooting possible.

The diagnostics file is stored here:

`~/Library/Application Support/photos-wallpaper/runtime.log`

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
4. It writes local history and diagnostics entries as described above.

That is the whole loop.
