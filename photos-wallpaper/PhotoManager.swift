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

enum PhotoAccessPreflightResult {
    case ready
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

enum PhotosWallpaperAlbumAddResult: Equatable {
    case added
    case alreadyInAlbum
}

@MainActor
protocol PhotoManaging: AnyObject {
    func addPhotoAuthorizationChangeHandler(_ handler: @escaping () -> Void)
    func getRandomPhotos(for displayOrientations: [WallpaperOrientation]) -> PhotoSelectionResult
    func requestPhotoAccessIfNeeded() -> PhotoAccessPreflightResult
    func identifier(for asset: PHAsset) -> String
    func requestDisplayName(for asset: PHAsset, completion: @escaping @MainActor (String) -> Void)
    func findPhoto(localIdentifier: String) -> PhotoAssetLookupResult
    func findPhotos(localIdentifiers: [String]) -> PhotoAssetsLookupResult
    func managedCurrentWallpaperIdentifiers() -> [String]
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping @MainActor (NSImage?) -> Void) -> PhotoImageRequest
    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void)
    func setImageAsWallpaper(_ image: NSImage, from asset: PHAsset, for screen: NSScreen) -> Bool
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
@MainActor
final class PhotoManager: PhotoManaging {
    static let shared = PhotoManager()
    private static let photosWallpaperAlbumTitle = "Photos Wallpaper"

    private let wallpaperManager: WallpaperManaging
    private let screenProvider: ScreenProviding
    private let cacheDirectoryURL: URL?
    private var allPhotos: PHFetchResult<PHAsset>?
    private var hasRequestedPhotoAccess = false
    private let albumQueue = AlbumRequestQueue()
    private var albumIdentifier: String?
    private let metadataQueue = DispatchQueue(label: "photos-wallpaper.metadata", qos: .utility)
    private var photoAuthorizationChangeHandlers: [() -> Void] = []

    init(wallpaperManager: WallpaperManaging? = nil,
         screenProvider: ScreenProviding? = nil,
         cacheDirectoryURL: URL? = nil) {
        self.wallpaperManager = wallpaperManager ?? WallpaperManager()
        self.screenProvider = screenProvider ?? AppKitScreenProvider()
        self.cacheDirectoryURL = cacheDirectoryURL
    }

    func addPhotoAuthorizationChangeHandler(_ handler: @escaping () -> Void) {
        photoAuthorizationChangeHandlers.append(handler)
    }

    /// Returns one asset per connected display, preferring each display's visible orientation from
    /// a bounded random sample. Square displays can use any photo shape.
    func getRandomPhotos(for displayOrientations: [WallpaperOrientation]) -> PhotoSelectionResult {
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

        guard !displayOrientations.isEmpty else {
            debugLog("PhotoManager: cannot select photos because no display orientations were provided.")
            return .unavailable
        }

        let photosCount = allPhotos?.count ?? 0
        guard let allPhotos, photosCount > 0 else {
            debugLog("PhotoManager: cannot select photos because the Photos library has no available image assets.")
            return .unavailable
        }
        debugLog("PhotoManager: selecting photos for \(displayOrientations.count) screen(s) from \(photosCount) library asset(s).")
        let selectedIndexes = selectedPhotoIndexes(for: displayOrientations, allPhotos: allPhotos)
        let selectedPhotos = selectedIndexes.map { allPhotos.object(at: $0) }
        debugLog("PhotoManager: selected \(selectedPhotos.count) photo asset(s).")
        return .photos(selectedPhotos)
    }

    private func selectedPhotoIndexes(for displayOrientations: [WallpaperOrientation],
                                      allPhotos: PHFetchResult<PHAsset>) -> [Int] {
        return WallpaperPhotoSelector.indexes(for: displayOrientations,
                                              photoCount: allPhotos.count) { index in
            let asset = allPhotos.object(at: index)
            return WallpaperOrientation(size: CGSize(width: asset.pixelWidth, height: asset.pixelHeight))
        }
    }

    /// Returns a human-friendly label that is still unique enough to disambiguate duplicates.
    ///
    /// `PHAsset` itself is mostly metadata and identifiers. `PHAssetResource` is where Photos
    /// exposes the original asset filename such as `IMG_6790.HEIC`. The label includes creation
    /// date when available for human lookup in Photos, plus the Photos `localIdentifier` as a
    /// technical fallback for exact disambiguation.
    func identifier(for asset: PHAsset) -> String { asset.localIdentifier }

    func requestDisplayName(for asset: PHAsset, completion: @escaping @MainActor (String) -> Void) {
        metadataQueue.async {
            let name = Self.assetDescription(asset)
            Task { @MainActor in completion(name) }
        }
    }

    nonisolated private static func assetDescription(_ asset: PHAsset) -> String {
        guard let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename else {
            return asset.localIdentifier
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm:ss"
        return PhotoHistoryAssetDescriptionFormatter.string(filename: filename,
            creationDate: asset.creationDate, localIdentifier: asset.localIdentifier,
            dateFormatter: formatter)
    }

    func findPhoto(localIdentifier: String) -> PhotoAssetLookupResult {
        let trimmedIdentifier = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return .notFound }

        switch findPhotos(localIdentifiers: [trimmedIdentifier]) {
        case .photos(let assets, _):
            guard let asset = assets.first else {
                debugLog("PhotoManager: no Photos asset matched local identifier \(trimmedIdentifier).")
                return .notFound
            }
            debugLog("PhotoManager: found a Photos asset for local identifier \(trimmedIdentifier).")
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

        switch requestPhotoAccessIfNeeded() {
        case .ready:
            let result = PHAsset.fetchAssets(withLocalIdentifiers: trimmedIdentifiers, options: nil)
            var assetsByIdentifier = [String: PHAsset]()
            result.enumerateObjects { asset, _, _ in
                assetsByIdentifier[asset.localIdentifier] = asset
            }

            let assets = trimmedIdentifiers.compactMap { assetsByIdentifier[$0] }
            let missingIdentifierCount = trimmedIdentifiers.count - assets.count
            debugLog("PhotoManager: matched \(assets.count) of \(trimmedIdentifiers.count) requested Photos local identifier(s).")
            if missingIdentifierCount > 0 {
                debugLog("PhotoManager: \(missingIdentifierCount) requested Photos local identifier(s) did not match an asset.")
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

    /// Returns the Photos identifiers encoded in the generated files that macOS currently uses.
    ///
    /// The identifier travels with the wallpaper file rather than a positional "Screen 1" key, so
    /// unplugging or rearranging displays cannot associate a desktop with another screen's photo.
    func managedCurrentWallpaperIdentifiers() -> [String] {
        let cacheDirectoryURL = wallpaperCacheDirectoryURL()
        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()

        for screen in screenProvider.screens {
            guard let wallpaperURL = wallpaperManager.desktopImageURL(for: screen),
                  let identifier = Self.localIdentifier(inGeneratedWallpaperURL: wallpaperURL,
                                                        in: cacheDirectoryURL),
                  seenIdentifiers.insert(identifier).inserted else {
                continue
            }
            identifiers.append(identifier)
        }

        debugLog("PhotoManager: found \(identifiers.count) identifiable current wallpaper(s) managed by Photos Wallpaper.")
        return identifiers
    }

    static func isGeneratedWallpaperURL(_ wallpaperURL: URL, in cacheDirectoryURL: URL) -> Bool {
        let standardizedWallpaperURL = wallpaperURL.standardizedFileURL
        let standardizedCacheDirectoryURL = cacheDirectoryURL.standardizedFileURL
        guard standardizedWallpaperURL.deletingLastPathComponent() == standardizedCacheDirectoryURL else {
            return false
        }

        let filename = standardizedWallpaperURL.lastPathComponent
        return filename.hasPrefix("current-wallpaper-") && filename.hasSuffix(".jpg")
    }

    static func localIdentifier(inGeneratedWallpaperURL wallpaperURL: URL,
                                in cacheDirectoryURL: URL) -> String? {
        guard isGeneratedWallpaperURL(wallpaperURL, in: cacheDirectoryURL) else { return nil }

        let filename = wallpaperURL.lastPathComponent
        guard let markerRange = filename.range(of: ".asset-", options: .backwards),
              let extensionRange = filename.range(of: ".jpg", options: [.anchored, .backwards]),
              markerRange.upperBound < extensionRange.lowerBound else {
            return nil
        }

        let encodedIdentifier = String(filename[markerRange.upperBound..<extensionRange.lowerBound])
        return decodeWallpaperIdentifier(encodedIdentifier)
    }

    /// Asks Photos to render the chosen asset at approximately the screen size we plan to use.
    ///
    /// The Photos API is callback-based, so this remains asynchronous even though the rest of the
    /// app mostly uses direct method calls.
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping @MainActor (NSImage?) -> Void) -> PhotoImageRequest {
        debugLog("PhotoManager: requesting image for asset \(asset.localIdentifier) at \(Int(targetSize.width))x\(Int(targetSize.height)).")
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        // Many real libraries keep originals in iCloud. Allow Photos to download when needed rather
        // than treating cloud-only assets as random nil image requests.
        options.isNetworkAccessAllowed = true

        let manager = PHImageManager.default()
        let requestID = manager.requestImage(for: asset, targetSize: targetSize,
                                             contentMode: .aspectFill, options: options) { image, info in
            // Ignore intermediate representations and deliver all state changes on the main actor.
            guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
            let errorDescription = (info?[PHImageErrorKey] as? Error)?.localizedDescription
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            Task { @MainActor in
                if let errorDescription { debugLog("PhotoManager: image request failed: \(errorDescription)") }
                completion(cancelled ? nil : image)
            }
        }
        return PhotoImageRequest { manager.cancelImageRequest(requestID) }
    }

    /// All callers share this queue, including menu actions and concurrent AppleScript commands.
    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void) {
        albumQueue.enqueue(operation: { [self] finish in
            addToAlbum(asset: asset, completion: finish)
        }, completion: completion)
    }

    private func addToAlbum(asset: PHAsset, completion: @escaping (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void) {
        guard case .ready = requestPhotoAccessIfNeeded() else {
            completion(.failure(PhotosWallpaperAlbumError.albumUnavailable))
            return
        }
        if let album = fetchPhotosWallpaperAlbum() {
            add(asset: asset, to: album, completion: completion)
            return
        }

        let createdIdentifier = LockedValue<String?>(nil)
        let albumTitle = Self.photosWallpaperAlbumTitle
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
            createdIdentifier.set(request.placeholderForCreatedAssetCollection.localIdentifier)
        } completionHandler: { [self] success, error in
            Task { @MainActor in
                guard success, error == nil, let identifier = createdIdentifier.get(),
                      let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject else {
                    completion(.failure(error ?? PhotosWallpaperAlbumError.albumUnavailable))
                    return
                }
                albumIdentifier = identifier
                UserDefaults.standard.set(identifier, forKey: "photosWallpaperAlbumIdentifier")
                add(asset: asset, to: album, completion: completion)
            }
        }
    }

    /// Writes a rendered image to the app's wallpaper cache and applies it to one screen.
    ///
    /// `NSWorkspace` wants a file URL rather than raw image bytes, so this method materializes a
    /// JPEG file even though the image already exists in memory.
    func setImageAsWallpaper(_ image: NSImage, from asset: PHAsset, for screen: NSScreen) -> Bool {
        setImageAsWallpaper(image, assetLocalIdentifier: asset.localIdentifier, for: screen)
    }

    /// Takes an identifier separately so cache ownership can be tested without a Photos library.
    func setImageAsWallpaper(_ image: NSImage, assetLocalIdentifier: String, for screen: NSScreen) -> Bool {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let screenIdentifier = self.screenIdentifier(for: screen)
        let screenDescription = screenNumber.map { "display ID \($0)" } ?? "unknown display"
        guard let wallpaperURL = wallpaperFileURL(forScreenIdentifier: screenIdentifier,
                                                   assetLocalIdentifier: assetLocalIdentifier) else {
            debugLog("PhotoManager: could not create a wallpaper filename for \(screenDescription) because the Photos identifier was empty.")
            return false
        }

        // Avoid materializing and decoding a full TIFF between the raster and JPEG.
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let jpegData = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            debugLog("PhotoManager: failed to convert image into JPEG data for \(screenDescription).")
            return false
        }

        do {
            try prepareWallpaperCache(at: wallpaperURL.deletingLastPathComponent())
            try jpegData.write(to: wallpaperURL, options: .atomic)
            try markAsHiddenGeneratedWallpaperResource(wallpaperURL)
            debugLog("PhotoManager: wrote wallpaper file to \(wallpaperURL.path).")
            try wallpaperManager.setWallpaper(for: screen, to: wallpaperURL, options: WallpaperOptions())
            removeStaleWallpaperCacheFiles(protecting: wallpaperURL)
            debugLog("PhotoManager: set the wallpaper on \(screenDescription).")
            return true
        } catch {
            // A failed application must not leak the newly generated UUID-named file.
            if !screenProvider.screens.contains(where: { wallpaperManager.desktopImageURL(for: $0) == wallpaperURL }) {
                try? FileManager.default.removeItem(at: wallpaperURL)
            }
            debugLog("PhotoManager: failed to set the wallpaper on \(screenDescription): \(error).")
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

    private func wallpaperFileURL(forScreenIdentifier screenIdentifier: String,
                                  assetLocalIdentifier: String) -> URL? {
        let identifier = assetLocalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }
        let encodedIdentifier = Self.encodeWallpaperIdentifier(identifier)
        return wallpaperCacheDirectoryURL()
            .appendingPathComponent(
                "current-wallpaper-\(screenIdentifier)-\(UUID().uuidString).asset-\(encodedIdentifier).jpg")
    }

    private static func encodeWallpaperIdentifier(_ identifier: String) -> String {
        Data(identifier.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeWallpaperIdentifier(_ encodedIdentifier: String) -> String? {
        var base64 = encodedIdentifier
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let identifier = String(data: data, encoding: .utf8),
              !identifier.isEmpty else {
            return nil
        }
        return identifier
    }

    private func wallpaperCacheDirectoryURL() -> URL {
        if let cacheDirectoryURL { return cacheDirectoryURL }
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

    private func removeStaleWallpaperCacheFiles(protecting appliedURL: URL) {
        let cache = wallpaperCacheDirectoryURL()
        var protected = Set(screenProvider.screens.compactMap { wallpaperManager.desktopImageURL(for: $0)?.standardizedFileURL })
        protected.insert(appliedURL.standardizedFileURL)
        // Protect real current URLs, regardless of process lifetime or monitor count. Keep the
        // latest file per display and a seven-day grace period for other Spaces/disconnected screens.
        for directory in [cache, cache.deletingLastPathComponent()] {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            let files = contents.filter { isGeneratedWallpaperCacheFile($0) }.compactMap { url -> WallpaperCacheFile? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let date = values.contentModificationDate else { return nil }
                return WallpaperCacheFile(url: url, modifiedAt: date)
            }
            for url in WallpaperCachePolicy.removableFiles(files, protectedURLs: protected, now: Date()) {
                removeWallpaperCacheFile(url)
            }
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
            _ = requestPhotoAccessIfNeeded()
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

    func requestPhotoAccessIfNeeded() -> PhotoAccessPreflightResult {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return .ready
        case .notDetermined:
            break
        case .denied, .restricted:
            return .permissionDenied
        @unknown default:
            return .unavailable
        }

        guard !hasRequestedPhotoAccess else { return .waitingForAuthorization }
        hasRequestedPhotoAccess = true
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async { [weak self] in
                debugLog("PhotoManager: Photos authorization changed to \(Self.photoAuthorizationDescription(for: status)).")
                self?.photoAuthorizationChangeHandlers.forEach { $0() }
            }
        }
        return .waitingForAuthorization
    }

    /// Returns every image asset the app is currently allowed to see.
    private static func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        return PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }

    private func fetchPhotosWallpaperAlbum() -> PHAssetCollection? {
        let identifier = albumIdentifier ?? UserDefaults.standard.string(forKey: "photosWallpaperAlbumIdentifier")
        if let identifier,
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject,
           album.localizedTitle == Self.photosWallpaperAlbumTitle {
            return album
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", Self.photosWallpaperAlbumTitle)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        var candidates: [PHAssetCollection] = []
        albums.enumerateObjects { album, _, _ in candidates.append(album) }
        let album = candidates.sorted { $0.localIdentifier < $1.localIdentifier }.first
        if let album {
            albumIdentifier = album.localIdentifier
            UserDefaults.standard.set(album.localIdentifier, forKey: "photosWallpaperAlbumIdentifier")
        }
        return album
    }

    private static func album(_ album: PHAssetCollection, contains asset: PHAsset) -> Bool {
        let assets = PHAsset.fetchAssets(in: album, options: nil)
        var containsAsset = false
        assets.enumerateObjects { albumAsset, _, stop in
            guard albumAsset.localIdentifier == asset.localIdentifier else { return }
            containsAsset = true
            stop.pointee = true
        }
        return containsAsset
    }

    private func add(asset: PHAsset, to album: PHAssetCollection, completion: @escaping (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void) {
        guard !Self.album(album, contains: asset) else {
            debugLog("PhotoManager: asset \(asset.localIdentifier) is already in Photos Wallpaper album.")
            completion(.success(.alreadyInAlbum))
            return
        }

        let didCreateRequest = LockedValue(false)
        PHPhotoLibrary.shared().performChanges {
            guard let changeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            didCreateRequest.set(true)
            changeRequest.addAssets([asset] as NSArray)
        } completionHandler: { success, error in
            Task { @MainActor in
                completion(AlbumMutationOutcome.result(transactionSucceeded: success,
                    requestCreated: didCreateRequest.get(), containsAsset: Self.album(album, contains: asset), error: error))
            }
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
            return "not determined"
        @unknown default:
            return "unknown"
        }
    }

}
