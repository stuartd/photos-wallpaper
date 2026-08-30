import AppKit
import Foundation

@MainActor
protocol PhotosAlbumOpening {
    func openPhotosWallpaperAlbum() -> Bool
    func openPhotosApplication() -> Bool
}

@MainActor
final class AppKitPhotosAlbumOpener: PhotosAlbumOpening {
    static let albumTitle = "Photos Wallpaper"

    private let runAppleScript: (String) -> Bool
    private let openApplication: () -> Bool

    convenience init() {
        self.init(
            runAppleScript: Self.executeAppleScript,
            openApplication: Self.openPhotosApplication)
    }

    init(runAppleScript: @escaping (String) -> Bool,
         openApplication: @escaping () -> Bool) {
        self.runAppleScript = runAppleScript
        self.openApplication = openApplication
    }

    func openPhotosWallpaperAlbum() -> Bool {
        // Opening the application sends the same kind of request as choosing Photos from the
        // Dock. Unlike AppleScript's `activate`, it also gives a minimized Photos window a chance
        // to return to the screen. Run the album script afterwards so the requested album remains
        // the final selection.
        if !openApplication() {
            debugLog("AppKitPhotosAlbumOpener: could not bring Photos forward before selecting the album.")
        }

        let source = """
        tell application "/System/Applications/Photos.app"
            set matchingAlbums to every album whose name is "\(Self.albumTitle)"
            if (count of matchingAlbums) is 0 then error "\(Self.albumTitle) album was not found."
            spotlight item 1 of matchingAlbums
            activate
        end tell
        """

        let didOpen = runAppleScript(source)
        if didOpen {
            debugLog("AppKitPhotosAlbumOpener: opened the Photos Wallpaper album in Photos.")
        } else {
            debugLog("AppKitPhotosAlbumOpener: could not open the Photos Wallpaper album in Photos.")
        }
        return didOpen
    }

    func openPhotosApplication() -> Bool {
        let didOpen = openApplication()
        if didOpen {
            debugLog("AppKitPhotosAlbumOpener: opened Photos without selecting an album.")
        } else {
            debugLog("AppKitPhotosAlbumOpener: could not open Photos.")
        }
        return didOpen
    }

    private static func executeAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            debugLog("AppKitPhotosAlbumOpener: could not create the Photos album AppleScript.")
            return false
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return true }

        debugLog("AppKitPhotosAlbumOpener: Photos album AppleScript failed: \(errorInfo).")
        return false
    }

    private static func openPhotosApplication() -> Bool {
        guard let photosURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") else {
            debugLog("AppKitPhotosAlbumOpener: Photos application URL was not available.")
            return false
        }

        let didOpen = NSWorkspace.shared.open(photosURL)
        if didOpen,
           let photosApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Photos").first,
           !photosApplication.activate(options: [.activateAllWindows]) {
            debugLog("AppKitPhotosAlbumOpener: Photos did not accept the request to bring all windows forward.")
        }
        return didOpen
    }
}
