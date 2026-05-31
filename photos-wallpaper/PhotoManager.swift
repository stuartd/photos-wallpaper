import Foundation
import Photos
import AppKit

enum PhotoSelectionResult {
    case photos([PHAsset])
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

protocol PhotoManaging: AnyObject {
    func getRandomPhotos(count: Int) -> PhotoSelectionResult
    func displayName(for asset: PHAsset) -> String
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void)
    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) -> Bool
}

/// Bridges Photos.framework and wallpaper setting.
///
/// This type owns the "pick assets -> render NSImage -> write JPEG -> ask AppKit to use it"
/// part of the pipeline so the controller can stay focused on timing and screen coordination.
///
/// Quick Apple-framework glossary:
/// - `PHAsset`: a Photos library item; think "photo record/handle", not the image bytes themselves.
/// - `NSImage`: AppKit's image type on macOS.
/// - `NSScreen`: AppKit's representation of one connected display.
final class PhotoManager: PhotoManaging {
    static let shared = PhotoManager()

    private let wallpaperManager: WallpaperManaging
    private let wallpaperCacheLock = NSLock()
    private var allPhotos: PHFetchResult<PHAsset>?
    private var hasRequestedPhotoAccess = false
    private var activeWallpaperFilenamesByScreen = [String: String]()

    init(wallpaperManager: WallpaperManaging = WallpaperManager()) {
        self.wallpaperManager = wallpaperManager
    }

    /// Returns one asset per screen.
    ///
    /// If there are fewer assets than screens, the last selected asset is reused so every display
    /// still receives a wallpaper for this cycle.
    func getRandomPhotos(count: Int) -> PhotoSelectionResult {
        switch refreshPhotos() {
        case .ready:
            break
            
        // clunky but explicit
        case .waitingForAuthorization:
            return .waitingForAuthorization
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        }

        let photosCount = allPhotos?.count ?? 0
        guard count > 0, let allPhotos, photosCount > 0 else {
            debugLog("PhotoManager: no photos available for count \(count). Library count: \(photosCount).")
            return .unavailable
        }
        debugLog("PhotoManager: selecting photos for \(count) screen(s) from \(photosCount) library asset(s).")
        let selectionCount = min(count, photosCount)
        let selectedIndexes = Array(0..<photosCount).shuffled().prefix(selectionCount)
        var selectedPhotos = selectedIndexes.map { allPhotos.object(at: $0) }
        if let fallbackPhoto = selectedPhotos.last, selectedPhotos.count < count {
            selectedPhotos.append(contentsOf: Array(repeating: fallbackPhoto, count: count - selectedPhotos.count))
        }
        debugLog("PhotoManager: returning \(selectedPhotos.count) photo asset(s).")
        return .photos(selectedPhotos)
    }

    /// Returns a human-friendly label that is still unique enough to disambiguate duplicates.
    ///
    /// `PHAsset` itself is mostly metadata and identifiers. `PHAssetResource` is where Photos
    /// exposes the original asset filename such as `IMG_6790.HEIC`. The label includes creation
    /// date when available for human lookup in Photos, plus the Photos `localIdentifier` as a
    /// technical fallback for exact disambiguation.
    func displayName(for asset: PHAsset) -> String {
        let identifierSuffix = "id: \(asset.localIdentifier)"

        // Perform the potentially expensive filename lookup off the main thread to avoid
        // Photos.framework fetching on demand on the main queue.
        let filename: String? = {
            let fetch: () -> String? = {
                PHAssetResource.assetResources(for: asset).first?.originalFilename
            }
            if Thread.isMainThread {
                return DispatchQueue.global(qos: .userInitiated).sync(execute: fetch)
            } else {
                return fetch()
            }
        }()

        if let filename = filename {
            if let creationDate = asset.creationDate {
                return "\(filename) (created \(Self.historyAssetDateFormatter.string(from: creationDate)), \(identifierSuffix))"
            }
            return "\(filename) (\(identifierSuffix))"
        }
        return asset.localIdentifier
    }

    /// Asks Photos to render the chosen asset at approximately the screen size we plan to use.
    ///
    /// The Photos API is callback-based, so this remains asynchronous even though the rest of the
    /// app mostly uses direct method calls.
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        debugLog("PhotoManager: requesting image for asset \(asset.localIdentifier) at \(Int(targetSize.width))x\(Int(targetSize.height)).")
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        // Many real libraries keep originals in iCloud. Allow Photos to download when needed rather
        // than treating cloud-only assets as random nil image requests.
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            debugLog("PhotoManager: image request for asset \(asset.localIdentifier) completed with image: \(image != nil).")
            completion(image)
        }
    }

    /// Writes a rendered image to the app's wallpaper cache and applies it to one screen.
    ///
    /// `NSWorkspace` wants a file URL rather than raw image bytes, so this method materializes a
    /// JPEG file even though the image already exists in memory.
    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) -> Bool {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let screenIdentifier = self.screenIdentifier(for: screen)
        let screenDescription = screenNumber.map { "display ID \($0)" } ?? "unknown display"
        let wallpaperURL = wallpaperFileURL(forScreenIdentifier: screenIdentifier)

        // AppKit image conversion is a little old-school: NSImage -> TIFF -> bitmap rep -> JPEG.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            debugLog("PhotoManager: failed to convert image into JPEG data for \(screenDescription).")
            return false
        }

        do {
            try prepareWallpaperCache(at: wallpaperURL.deletingLastPathComponent())
            try jpegData.write(to: wallpaperURL, options: .atomic)
            try markAsHiddenGeneratedWallpaperResource(wallpaperURL)
            debugLog("PhotoManager: wrote wallpaper file to \(wallpaperURL.path).")
            try wallpaperManager.setWallpaper(for: screen, to: wallpaperURL, options: WallpaperOptions())
            wallpaperCacheLock.lock()
            defer { wallpaperCacheLock.unlock() }
            activeWallpaperFilenamesByScreen[screenIdentifier] = wallpaperURL.lastPathComponent
            if activeWallpaperFilenamesByScreen.count >= NSScreen.screens.count {
                removeStaleWallpaperCacheFiles()
                removeLegacyWallpaperCacheFiles()
            }
            debugLog("PhotoManager: wallpaper applied successfully to \(screenDescription).")
            return true
        } catch {
            debugLog("PhotoManager: failed to set wallpaper on \(screenDescription): \(error)")
            return false
        }
    }

    private enum PhotoRefreshResult {
        case ready
        case waitingForAuthorization
        case permissionDenied
        case unavailable
    }

    private func screenIdentifier(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return screenNumber.stringValue
        }

        let frame = screen.frame
        return "unknown-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))x\(Int(frame.height))"
    }

    private func wallpaperFileURL(forScreenIdentifier screenIdentifier: String) -> URL {
        wallpaperCacheDirectoryURL()
            .appendingPathComponent("current-wallpaper-\(screenIdentifier)-\(UUID().uuidString).jpg")
    }

    private func wallpaperCacheDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("photos-wallpaper", isDirectory: true)
            .appendingPathComponent(".WallpaperCache", isDirectory: true)
    }

    private func prepareWallpaperCache(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try markAsHiddenGeneratedWallpaperResource(directoryURL)
    }

    private func markAsHiddenGeneratedWallpaperResource(_ url: URL) throws {
        var values = URLResourceValues()
        values.isHidden = true
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func removeStaleWallpaperCacheFiles() {
        let cacheDirectory = wallpaperCacheDirectoryURL()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                          includingPropertiesForKeys: nil) else {
            return
        }

        let activeWallpaperFilenames = Set(activeWallpaperFilenamesByScreen.values)
        for url in contents where isGeneratedWallpaperCacheFile(url) && !activeWallpaperFilenames.contains(url.lastPathComponent) {
            removeWallpaperCacheFile(url)
        }
    }

    private func removeLegacyWallpaperCacheFiles() {
        let legacyCacheDirectory = wallpaperCacheDirectoryURL().deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: legacyCacheDirectory,
                                                                          includingPropertiesForKeys: nil,
                                                                          options: [.skipsHiddenFiles]) else {
            return
        }

        for url in contents where isGeneratedWallpaperCacheFile(url) {
            removeWallpaperCacheFile(url)
        }
    }

    private func isGeneratedWallpaperCacheFile(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        return filename.hasPrefix("current-wallpaper-") && filename.hasSuffix(".jpg")
    }

    private func removeWallpaperCacheFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            debugLog("PhotoManager: removed stale wallpaper cache file at \(url.path).")
        } catch {
            debugLog("PhotoManager: failed to remove stale wallpaper cache file at \(url.path): \(error).")
        }
    }

    /// Re-runs the Photos fetch each cycle so permission changes and new library contents are seen
    /// without restarting the menu bar app.
    ///
    /// PhotoKit has no read-only access level for existing assets: reading library photos uses
    /// `.readWrite`. This app only fetches and renders images; it never writes to the Photos library.
    private func refreshPhotos() -> PhotoRefreshResult {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            allPhotos = Self.fetchAllPhotos()
            debugLog("PhotoManager: refreshed library fetch. Current image asset count: \(allPhotos?.count ?? 0). Photos authorization: \(Self.photoAuthorizationDescription).")
            return .ready
        case .notDetermined:
            // Do not fetch before the user answers the system prompt. A pending permission request is
            // different from an empty library and should not trigger a "no photos" notification.
            requestPhotoAccessIfNeeded()
            debugLog("PhotoManager: waiting for Photos authorization before fetching assets.")
            return .waitingForAuthorization
        case .denied, .restricted:
            allPhotos = nil
            debugLog("PhotoManager: cannot fetch photos. Photos authorization: \(Self.photoAuthorizationDescription).")
            return .permissionDenied
        @unknown default:
            allPhotos = nil
            debugLog("PhotoManager: cannot fetch photos. Photos authorization: unknown.")
            return .unavailable
        }
    }

    private func requestPhotoAccessIfNeeded() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        guard !hasRequestedPhotoAccess else { return }
        hasRequestedPhotoAccess = true
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            debugLog("PhotoManager: Photos authorization changed to \(Self.photoAuthorizationDescription(for: status)).")
        }
    }

    /// Returns every image asset the app is currently allowed to see.
    private static func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        return PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }

    private static var photoAuthorizationDescription: String {
        photoAuthorizationDescription(for: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func photoAuthorizationDescription(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    private static let historyAssetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
