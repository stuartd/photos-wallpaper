# Privacy

`photos-wallpaper` is a local macOS utility.

## What The App Accesses

The app requests access to your Photos library so it can choose images and use them as desktop wallpaper.

## What The App Stores

The app stores:

- your selected wallpaper cycle frequency
- a local wallpaper history log

The history log is written to:

- `~/Library/Application Support/photos-wallpaper/wallpaper-history.log`

That log may include:

- photo filename
- photo creation date
- Photos asset identifier
- monitor number
- timestamp when the wallpaper was applied

## What The App Does Not Do

The app does not:

- upload your photos
- upload your wallpaper history
- create an online account
- send your data to a server
- use analytics or advertising services

## Data Flow

All processing happens locally on your Mac.

The app reads image data from your Photos library, asks macOS to set desktop wallpaper, and writes the local history log described above.

## Permissions

The app asks for Photos permission because macOS requires that access before an app can read images from your Photos library.
