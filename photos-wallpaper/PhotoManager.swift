import Foundation
import Photos
import AppKit

enum PhotoSelectionResult {
    case photos([PHAsset])
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

enum PhotoAssetLookupResult {
    case photo(PHAsset)
    case waitingForAuthorization
    case permissionDenied
    case notFound
    case unavailable
}

enum PhotoAssetsLookupResult {
    case photos([PHAsset], missingIdentifierCount: Int)
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

enum PhotosWallpaperAlbumError: LocalizedError {
    case albumUnavailable
    case assetCouldNotBeAdded

    var errorDescription: String? {
        switch self {
        case .albumUnavailable:
            return "Photos Wallpaper could not create or find the Photos Wallpaper album."
        case .assetCouldNotBeAdded:
            return "Photos Wallpaper could not add that photo to the Photos Wallpaper album."
        }
    }
}

protocol PhotoManaging: AnyObject {
    func getRandomPhotos(count: Int) -> PhotoSelectionResult
    func displayName(for asset: PHAsset) -> String
    func findPhoto(localIdentifier: String) -> PhotoAssetLookupResult
    func findPhotos(localIdentifiers: [String]) -> PhotoAssetsLookupResult
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void)
    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<Void, Error>) -> Void)
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
    private static let photosWallpaperAlbumTitle = "Photos Wallpaper"

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
            return PhotoHistoryAssetDescriptionFormatter.string(filename: filename,
                                                                creationDate: asset.creationDate,
                                                                localIdentifier: asset.localIdentifier,
                                                                dateFormatter: Self.historyAssetDateFormatter)
        }
        return asset.localIdentifier
    }

    func findPhoto(localIdentifier: String) -> PhotoAssetLookupResult {
        let trimmedIdentifier = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return .notFound }

        switch findPhotos(localIdentifiers: [trimmedIdentifier]) {
        case .photos(let assets, _):
            guard let asset = assets.first else {
                debugLog("PhotoManager: no Photos asset found for history identifier \(trimmedIdentifier).")
                return .notFound
            }
            debugLog("PhotoManager: found Photos asset for history identifier \(trimmedIdentifier).")
            return .photo(asset)
        case .waitingForAuthorization:
            return .waitingForAuthorization
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        }
    }

    func findPhotos(localIdentifiers: [String]) -> PhotoAssetsLookupResult {
        let trimmedIdentifiers = localIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedIdentifiers.isEmpty else {
            return .photos([], missingIdentifierCount: 0)
        }

        switch refreshPhotos() {
        case .ready:
            let result = PHAsset.fetchAssets(withLocalIdentifiers: trimmedIdentifiers, options: nil)
            var assetsByIdentifier = [String: PHAsset]()
            result.enumerateObjects { asset, _, _ in
                assetsByIdentifier[asset.localIdentifier] = asset
            }

            let assets = trimmedIdentifiers.compactMap { assetsByIdentifier[$0] }
            let missingIdentifierCount = trimmedIdentifiers.count - assets.count
            debugLog("PhotoManager: found \(assets.count) Photos asset(s) for \(trimmedIdentifiers.count) history identifier(s).")
            if missingIdentifierCount > 0 {
                debugLog("PhotoManager: \(missingIdentifierCount) history identifier(s) were not found in Photos.")
            }
            return .photos(assets, missingIdentifierCount: missingIdentifierCount)
        case .waitingForAuthorization:
            return .waitingForAuthorization
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        }
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

    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<Void, Error>) -> Void) {
        switch refreshPhotos() {
        case .ready:
            break
        case .waitingForAuthorization:
            completion(.failure(PhotosWallpaperAlbumError.albumUnavailable))
            return
        case .permissionDenied:
            completion(.failure(PhotosWallpaperAlbumError.assetCouldNotBeAdded))
            return
        case .unavailable:
            completion(.failure(PhotosWallpaperAlbumError.albumUnavailable))
            return
        }

        if let album = Self.fetchPhotosWallpaperAlbum() {
            add(asset: asset, to: album, completion: completion)
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.photosWallpaperAlbumTitle)
        } completionHandler: { [weak self] success, error in
            if let error {
                debugLog("PhotoManager: failed to create Photos Wallpaper album: \(error).")
                completion(.failure(error))
                return
            }

            guard success, let album = Self.fetchPhotosWallpaperAlbum() else {
                debugLog("PhotoManager: Photos Wallpaper album was not available after creation.")
                completion(.failure(PhotosWallpaperAlbumError.albumUnavailable))
                return
            }

            self?.add(asset: asset, to: album, completion: completion)
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
    /// PhotoKit uses `.readWrite` here because the app can both read wallpaper assets and add
    /// selected current wallpapers to the Photos Wallpaper album.
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

    private static func fetchPhotosWallpaperAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", photosWallpaperAlbumTitle)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }

    private func add(asset: PHAsset, to album: PHAssetCollection, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            guard let changeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            changeRequest.addAssets([asset] as NSArray)
        } completionHandler: { success, error in
            if let error {
                debugLog("PhotoManager: failed to add asset \(asset.localIdentifier) to Photos Wallpaper album: \(error).")
                completion(.failure(error))
                return
            }

            guard success else {
                debugLog("PhotoManager: Photos did not add asset \(asset.localIdentifier) to Photos Wallpaper album.")
                completion(.failure(PhotosWallpaperAlbumError.assetCouldNotBeAdded))
                return
            }

            debugLog("PhotoManager: added asset \(asset.localIdentifier) to Photos Wallpaper album.")
            completion(.success(()))
        }
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
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm:ss"
        return formatter
    }()
}
