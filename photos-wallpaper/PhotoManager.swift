import Foundation
import Photos
import AppKit

private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

protocol PhotoManaging: AnyObject {
    func getRandomPhotos(count: Int) -> [PHAsset]
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void)
    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen)
}

final class PhotoManager: PhotoManaging {
    static let shared = PhotoManager()

    private let wallpaperManager: WallpaperManaging
    private var allPhotos: PHFetchResult<PHAsset>

    /// Fetches the initial image asset list so the wallpaper cycle can later select random photos from the library.
    init(wallpaperManager: WallpaperManaging = WallpaperManager()) {
        self.wallpaperManager = wallpaperManager
        allPhotos = Self.fetchAllPhotos()
    }
    
    /// Returns enough random photo assets for the requested display count, reusing the last selected asset when photos run short.
    func getRandomPhotos(count: Int) -> [PHAsset] {
        refreshPhotos()
        // Stop early when there are no screens to fill or no image assets available.
        guard count > 0, allPhotos.count > 0 else {
            debugLog("PhotoManager: no photos available for count \(count). Library count: \(allPhotos.count).")
            return []
        }
        debugLog("PhotoManager: selecting photos for \(count) screen(s) from \(allPhotos.count) library asset(s).")
        // Pick as many distinct assets as the library can provide for this cycle.
        let selectionCount = min(count, allPhotos.count)
        // Shuffle asset indexes so the selection is unique within one wallpaper cycle.
        let selectedIndexes = Array(0..<allPhotos.count).shuffled().prefix(selectionCount)
        // Map the chosen indexes back into the fetched asset collection.
        var selectedPhotos = selectedIndexes.map { allPhotos.object(at: $0) }
        // Reuse the last selected photo for any remaining displays once the library runs out of distinct choices.
        if let fallbackPhoto = selectedPhotos.last, selectedPhotos.count < count {
            selectedPhotos.append(contentsOf: Array(repeating: fallbackPhoto, count: count - selectedPhotos.count))
        }
        debugLog("PhotoManager: returning \(selectedPhotos.count) photo asset(s).")
        return selectedPhotos
    }
    
    /// Requests an `NSImage` for a selected photo asset so the next step can turn it into a desktop wallpaper file.
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        debugLog("PhotoManager: requesting image for asset \(asset.localIdentifier) at \(Int(targetSize.width))x\(Int(targetSize.height)).")
        // Create Photos image request options to control how the image is delivered.
        let options = PHImageRequestOptions()
        // Keep the request asynchronous so the app does not block while Photos renders the image.
        options.isSynchronous = false
        // Ask Photos for a high-quality image suitable for use as wallpaper.
        options.deliveryMode = .highQualityFormat
        
        // Submit the image request for the selected asset using the desired target size and fill mode.
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            debugLog("PhotoManager: image request for asset \(asset.localIdentifier) completed with image: \(image != nil).")
            // Forward the resulting image, if any, to the caller so the wallpaper-setting chain can continue.
            completion(image)
        }
    }
    
    /// Converts a loaded image into a temporary JPEG file and asks macOS to apply it to the specified display.
    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) {
        // Locate the system temporary directory for writing the intermediate wallpaper image file.
        let tempDir = FileManager.default.temporaryDirectory
        // Build a unique temporary file URL so macOS does not keep reusing a cached wallpaper image for the same path.
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let screenIdentifier = screenNumber?.stringValue ?? UUID().uuidString
        let tempURL = tempDir.appendingPathComponent("tempWallpaper-\(screenIdentifier)-\(UUID().uuidString).jpg")
        
        // Convert NSImage to JPEG data
        // Extract TIFF data, convert it to a bitmap, and then encode that bitmap as JPEG data.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            debugLog("PhotoManager: failed to convert image into JPEG data for screen \(screenIdentifier).")
            return
        }
        
        // Write the JPEG to disk and ask `NSWorkspace` to use it as the wallpaper for the targeted screen.
        do {
            try jpegData.write(to: tempURL)
            debugLog("PhotoManager: wrote temporary wallpaper file to \(tempURL.path).")
            try wallpaperManager.setWallpaper(for: screen, to: tempURL, options: WallpaperOptions())
            debugLog("PhotoManager: wallpaper applied successfully to screen \(screenIdentifier).")
        } catch {
            // Log the failure so wallpaper update problems are visible during development.
            debugLog("PhotoManager: failed to set wallpaper on screen \(screenIdentifier): \(error)")
        }
    }

    /// Refreshes the cached photo fetch so newly granted permissions and library changes are visible without restarting the app.
    private func refreshPhotos() {
        allPhotos = Self.fetchAllPhotos()
        debugLog("PhotoManager: refreshed library fetch. Current image asset count: \(allPhotos.count).")
    }

    /// Fetches all image assets currently visible to the app from the Photos library.
    private static func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        return PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }
}
