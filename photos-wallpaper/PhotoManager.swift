import Foundation
import Photos
import AppKit

protocol PhotoManaging: AnyObject {
    func getRandomPhoto() -> PHAsset?
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void)
    func setImageAsWallpaper(_ image: NSImage)
}

final class PhotoManager: PhotoManaging {
    static let shared = PhotoManager()

    private let wallpaperManager: WallpaperManaging
    private var allPhotos: PHFetchResult<PHAsset>

    /// Fetches the initial image asset list so the wallpaper cycle can later select random photos from the library.
    init(wallpaperManager: WallpaperManaging = WallpaperManager()) {
        self.wallpaperManager = wallpaperManager
        // Create fetch options for the Photos query; they are empty for now so all image assets are included.
        let fetchOptions = PHFetchOptions()
        // TODO this doesn't use new photos until the app is restarted
        // Execute the Photos fetch and store the complete image asset result for later random access.
        allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }
    
    /// Returns one random photo asset from the cached fetch result as the first step in the wallpaper update chain.
    func getRandomPhoto() -> PHAsset? {
        // Stop early when the photo fetch contains no image assets to choose from.
        guard allPhotos.count > 0 else { return nil }
        // Pick a random valid index into the fetched asset collection.
        let randomIndex = Int.random(in: 0..<allPhotos.count)
        // Return the asset at the chosen index so later steps can request image data for it.
        return allPhotos.object(at: randomIndex)
    }
    
    /// Requests an `NSImage` for a selected photo asset so the next step can turn it into a desktop wallpaper file.
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        // Create Photos image request options to control how the image is delivered.
        let options = PHImageRequestOptions()
        // Keep the request asynchronous so the app does not block while Photos renders the image.
        options.isSynchronous = false
        // Ask Photos for a high-quality image suitable for use as wallpaper.
        options.deliveryMode = .highQualityFormat
        
        // Submit the image request for the selected asset using the desired target size and fill mode.
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            // Forward the resulting image, if any, to the caller so the wallpaper-setting chain can continue.
            completion(image)
        }
    }
    
    /// Converts a loaded image into a temporary JPEG file and asks macOS to apply it as the current wallpaper.
    func setImageAsWallpaper(_ image: NSImage) {
        // Stop if the app cannot resolve a main screen to target for the wallpaper update.
        guard let screen = NSScreen.main else { return }
        // Locate the system temporary directory for writing the intermediate wallpaper image file.
        let tempDir = FileManager.default.temporaryDirectory
        // Build the temporary file URL used for the wallpaper image written in the next step.
        let tempURL = tempDir.appendingPathComponent("tempWallpaper.jpg")
        
        // Convert NSImage to JPEG data
        // Extract TIFF data, convert it to a bitmap, and then encode that bitmap as JPEG data.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else { return }
        
        // Write the JPEG to disk and ask `NSWorkspace` to use it as the wallpaper for the main screen.
        do {
            try jpegData.write(to: tempURL)
            try wallpaperManager.setWallpaper(for: screen, to: tempURL, options: WallpaperOptions())
        } catch {
            // Log the failure so wallpaper update problems are visible during development.
            print("Failed to set wallpaper: \(error)")
        }
    }
}
