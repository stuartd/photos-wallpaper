import Foundation
import Photos
import AppKit
import CoreGraphics
import Vision

/// PhotoKit fetches, local cache I/O, and Vision work run on this actor, away from the main actor.
actor PhotoUtilityClassifier: WallpaperCandidateProviding {
    private var cache: PhotoUtilityCache?

    func candidates(limit: Int, excluding: Set<String>) -> [WallpaperPhotoCandidate] {
        guard Self.canReadPhotos else { return [] }
        let options = PHFetchOptions()
        // Exclude screenshots in the metadata query, even in a library dominated by screenshots.
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        let photos = PHAsset.fetchAssets(with: .image, options: options)
        // Partial Fisher-Yates sampling: O(limit) metadata, no full-library array or scan.
        var swaps: [Int: Int] = [:]
        var result: [WallpaperPhotoCandidate] = []
        for i in 0..<min(limit + excluding.count, photos.count) {
            let j = Int.random(in: i..<photos.count)
            let index = swaps[j, default: j]
            swaps[j] = swaps[i, default: i]
            let candidate = Self.candidate(photos.object(at: index))
            if !excluding.contains(candidate.identifier) { result.append(candidate) }
            if result.count == limit { break }
        }
        return result
    }

    func currentCandidates(_ candidates: [WallpaperPhotoCandidate]) -> [WallpaperPhotoCandidate] {
        guard Self.canReadPhotos else { return [] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: candidates.map(\.identifier), options: nil)
        var current: [WallpaperPhotoCandidate] = []
        assets.enumerateObjects { asset, _, _ in
            let candidate = Self.candidate(asset)
            if !candidate.isScreenshot, candidates.contains(candidate) { current.append(candidate) }
        }
        return current
    }

    func isUtility(_ candidate: WallpaperPhotoCandidate) async -> Bool? {
        guard Self.canReadPhotos, !Task.isCancelled else { return nil }
        // Vision utility classification requires macOS 15. Older supported Macs still exclude
        // screenshots via PhotoKit, but cannot run this part of the best-effort filter.
        if #unavailable(macOS 15.0) { return false }
        if cache == nil {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("photos-wallpaper", isDirectory: true)
            cache = PhotoUtilityCache(url: directory?.appendingPathComponent("utility-classifications-v1.json"))
        }
        if let result = cache?.result(for: candidate) { return result }
        guard #available(macOS 15.0, *),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.identifier], options: nil).firstObject,
              Self.candidate(asset) == candidate,
              let image = await Self.thumbnail(for: asset), !Task.isCancelled else { return nil }
        do {
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image)
            guard !Task.isCancelled else { return nil }
            cache?.record(observation.isUtility, for: candidate)
            return observation.isUtility
        } catch {
            return nil
        }
    }

    nonisolated private static var canReadPhotos: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    nonisolated private static func candidate(_ asset: PHAsset) -> WallpaperPhotoCandidate {
        WallpaperPhotoCandidate(identifier: asset.localIdentifier, modificationDate: asset.modificationDate,
            orientation: WallpaperOrientation(size: CGSize(width: asset.pixelWidth, height: asset.pixelHeight)),
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot))
    }

    /// PhotoKit supplies an upright, edited rendition. Vision sees its full aspect ratio at 512px;
    /// this temporary image is released after classification, never added to the reference queue.
    nonisolated private static func thumbnail(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let pending = LockedValue<CheckedContinuation<CGImage?, Never>?>(continuation)
            // Serialize completion and timeout so the continuation can be resumed only once.
            let completionQueue = DispatchQueue(label: "photos-wallpaper.utility-thumbnail")
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.version = .current
            let requestID = manager.requestImage(for: asset, targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit, options: options) { image, info in
                guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                completionQueue.async {
                    guard let continuation = pending.get() else { return }
                    pending.set(nil)
                    continuation.resume(returning: cgImage)
                }
            }
            completionQueue.asyncAfter(deadline: .now() + 2) {
                guard let continuation = pending.get() else { return }
                pending.set(nil)
                manager.cancelImageRequest(requestID)
                continuation.resume(returning: nil)
            }
        }
    }
}

nonisolated final class WallpaperLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let changed: @Sendable () -> Void
    init(changed: @escaping @Sendable () -> Void) { self.changed = changed }
    func photoLibraryDidChange(_ changeInstance: PHChange) { changed() }
}
