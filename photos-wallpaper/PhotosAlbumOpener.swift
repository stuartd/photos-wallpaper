import AppKit
import Foundation

@MainActor
protocol PhotosAlbumOpening {
    func openPhotosWallpaperAlbum() async -> Bool
    func openPhotosApplication() -> Bool
}

@MainActor
final class AppKitPhotosAlbumOpener: PhotosAlbumOpening {
    static let albumTitle = "Photos Wallpaper"

    private let runAppleScript: (String) async -> Bool
    nonisolated private static let scriptQueue = DispatchQueue(label: "photos-wallpaper.apple-script", qos: .userInitiated)
    private let openApplication: () -> Bool

    convenience init() {
        self.init(
            runAppleScript: Self.executeAppleScript,
            openApplication: Self.openPhotosApplication)
    }

    init(runAppleScript: @escaping (String) async -> Bool,
         openApplication: @escaping () -> Bool) {
        self.runAppleScript = runAppleScript
        self.openApplication = openApplication
    }

    func openPhotosWallpaperAlbum() async -> Bool {
        // Opening the application sends the same kind of request as choosing Photos from the
        // Dock. Unlike AppleScript's `activate`, it also gives a minimized Photos window a chance
        // to return to the screen. Run the album script afterwards so the requested album remains
        // the final selection.
        if !openApplication() {
            debugLog("AppKitPhotosAlbumOpener: could not bring Photos forward before selecting the album.")
        }

        let identifier = UserDefaults.standard.string(forKey: "photosWallpaperAlbumIdentifier")
        let escapedIdentifier = (identifier ?? "").replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        with timeout of 20 seconds
        tell application "/System/Applications/Photos.app"
            set matchingAlbums to every album whose name is "\(Self.albumTitle)"
            if (count of matchingAlbums) is 0 then error "\(Self.albumTitle) album was not found."
            if (count of matchingAlbums) > 1 then
                set matchingAlbums to every album whose id is "\(escapedIdentifier)"
                if (count of matchingAlbums) is not 1 then error "More than one Photos Wallpaper album exists. Select the album manually in Photos."
            end if
            spotlight item 1 of matchingAlbums
            activate
        end tell
        end timeout
        """

        let didOpen = await runAppleScript(source)
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

    nonisolated private static func executeAppleScript(_ source: String) async -> Bool {
        // NSAppleScript supports secondary threads when all script work is serialized.
        // Apple DTS: https://developer.apple.com/forums/thread/759287
        // Keep creation, execution and disposal on the same queue. Apple events have an
        // explicit timeout in the script; no AppKit UI work is done on this queue.
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                let success = autoreleasepool {
                    guard let script = NSAppleScript(source: source) else { return false }
                    var errorInfo: NSDictionary?
                    script.executeAndReturnError(&errorInfo)
                    if let errorInfo { debugLog("Photos album AppleScript failed: \(errorInfo)") }
                    return errorInfo == nil
                }
                continuation.resume(returning: success)
            }
        }
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
