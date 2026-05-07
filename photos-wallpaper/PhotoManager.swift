import Foundation
import Photos
import AppKit

protocol PhotoManaging: AnyObject {
    func getRandomPhotos(count: Int) -> [PHAsset]
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
    private var allPhotos: PHFetchResult<PHAsset>

    init(wallpaperManager: WallpaperManaging = WallpaperManager()) {
        self.wallpaperManager = wallpaperManager
        allPhotos = Self.fetchAllPhotos()
    }

    /// Returns one asset per screen.
    ///
    /// If there are fewer assets than screens, the last selected asset is reused so every display
    /// still receives a wallpaper for this cycle.
    func getRandomPhotos(count: Int) -> [PHAsset] {
        refreshPhotos()
        guard count > 0, allPhotos.count > 0 else {
            debugLog("PhotoManager: no photos available for count \(count). Library count: \(allPhotos.count).")
            return []
        }
        debugLog("PhotoManager: selecting photos for \(count) screen(s) from \(allPhotos.count) library asset(s).")
        let selectionCount = min(count, allPhotos.count)
        let selectedIndexes = Array(0..<allPhotos.count).shuffled().prefix(selectionCount)
        var selectedPhotos = selectedIndexes.map { allPhotos.object(at: $0) }
        if let fallbackPhoto = selectedPhotos.last, selectedPhotos.count < count {
            selectedPhotos.append(contentsOf: Array(repeating: fallbackPhoto, count: count - selectedPhotos.count))
        }
        debugLog("PhotoManager: returning \(selectedPhotos.count) photo asset(s).")
        return selectedPhotos
    }

    /// Returns a human-friendly label that is still unique enough to disambiguate duplicates.
    ///
    /// `PHAsset` itself is mostly metadata and identifiers. `PHAssetResource` is where Photos
    /// exposes the original asset filename such as `IMG_6790.HEIC`. The label includes creation
    /// date when available for human lookup in Photos, plus the Photos `localIdentifier` as a
    /// technical fallback for exact disambiguation.
    func displayName(for asset: PHAsset) -> String {
        let identifierSuffix = "id: \(asset.localIdentifier)"
        if let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename {
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

        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            debugLog("PhotoManager: image request for asset \(asset.localIdentifier) completed with image: \(image != nil).")
            completion(image)
        }
    }

    /// Writes a rendered image to a temporary JPEG file and applies it to one screen.
    ///
    /// `NSWorkspace` wants a file URL rather than raw image bytes, so this method materializes a
    /// temporary file even though the image already exists in memory.
    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let screenIdentifier = screenNumber?.stringValue ?? UUID().uuidString
        let tempURL = tempDir.appendingPathComponent("tempWallpaper-\(screenIdentifier)-\(UUID().uuidString).jpg")

        // AppKit image conversion is a little old-school: NSImage -> TIFF -> bitmap rep -> JPEG.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            debugLog("PhotoManager: failed to convert image into JPEG data for screen \(screenIdentifier).")
            return false
        }

        do {
            try jpegData.write(to: tempURL)
            debugLog("PhotoManager: wrote temporary wallpaper file to \(tempURL.path).")
            try wallpaperManager.setWallpaper(for: screen, to: tempURL, options: WallpaperOptions())
            debugLog("PhotoManager: wallpaper applied successfully to screen \(screenIdentifier).")
            return true
        } catch {
            debugLog("PhotoManager: failed to set wallpaper on screen \(screenIdentifier): \(error)")
            return false
        }
    }

    /// Re-runs the Photos fetch each cycle so permission changes and new library contents are seen
    /// without restarting the menu bar app.
    private func refreshPhotos() {
        allPhotos = Self.fetchAllPhotos()
        debugLog("PhotoManager: refreshed library fetch. Current image asset count: \(allPhotos.count).")
    }

    /// Returns every image asset the app is currently allowed to see.
    private static func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        return PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }

    private static let historyAssetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
