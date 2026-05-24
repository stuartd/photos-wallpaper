# Privacy

`photos-wallpaper` is a local macOS utility.

## What The App Accesses

The app requests access to your Photos library so it can choose random images to use them as desktop wallpaper. It reads images only and does not modify your Photos library.

## What The App Stores

The app stores:

- your selected wallpaper cycle frequency
- whether the app should start at login, if you enable that option in macOS
- a local wallpaper history log
- a local runtime diagnostics log

The wallpaper history log is written to:

- `~/Library/Application Support/photos-wallpaper/wallpaper-history.log`

That history log may include:

- photo filename
- photo creation date
- Photos asset identifier
- screen number (for multiple screens)
- timestamp when the wallpaper was applied

The runtime diagnostics log is written to:

- `~/Library/Application Support/photos-wallpaper/runtime.log`

That diagnostics log may include:

- wallpaper cycle timing and schedule changes
- Photos library asset counts and selected Photos asset identifiers
- temporary wallpaper file paths
- success or failure messages from wallpaper updates
- app errors useful for troubleshooting

## What The App Does Not Do

The app does not:

- upload your photos
- upload your wallpaper history
- upload your runtime diagnostics log
- create an online account
- send your data to a server
- use analytics or advertising services

## Data Flow

All processing happens locally on your Mac.

The app reads image data from your Photos library, asks macOS to set desktop wallpaper, and writes the local history and diagnostics logs described above.

## Permissions

The app asks for Photos permission because macOS requires that access before an app can read images from your Photos library.
