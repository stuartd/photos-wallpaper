import Foundation
import Photos
import AppKit

class PhotoManager {
    static let shared = PhotoManager()
    
    var allPhotos: PHFetchResult<PHAsset>
    
    init() {
        let fetchOptions = PHFetchOptions()
        allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }
    
    func getRandomPhoto() -> PHAsset? {
        guard allPhotos.count > 0 else { return nil }
        let randomIndex = Int.random(in: 0..<allPhotos.count)
        return allPhotos.object(at: randomIndex)
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }
    
    func setImageAsWallpaper(_ image: NSImage) {
        guard let screen = NSScreen.main else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("tempWallpaper.jpg")
        
        // Convert NSImage to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else { return }
        
        do {
            try jpegData.write(to: tempURL)
            try NSWorkspace.shared.setDesktopImageURL(tempURL, for: screen, options: [:])
        } catch {
            print("Failed to set wallpaper: \(error)")
        }
    }
    
    
}
