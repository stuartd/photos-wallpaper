import AppKit
import Photos

enum CurrentWallpaperAlbumAdditionResult: Equatable {
    case added(addedCount: Int, missingIdentifierCount: Int, failedAddCount: Int)
    case noRememberedWallpapers
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

struct CurrentWallpaperAlbumAdder {
    let photoManager: PhotoManaging

    func addWallpapers(withLocalIdentifiers identifiers: [String],
                       completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        let identifiers = deduplicatedIdentifiers(identifiers)
        guard !identifiers.isEmpty else {
            completion(.noRememberedWallpapers)
            return
        }

        switch photoManager.findPhotos(localIdentifiers: identifiers) {
        case .photos(let assets, let missingIdentifierCount):
            addAssetsToAlbum(assets,
                             missingIdentifierCount: missingIdentifierCount,
                             completion: completion)
        case .waitingForAuthorization:
            completion(.waitingForAuthorization)
        case .permissionDenied:
            completion(.permissionDenied)
        case .unavailable:
            completion(.unavailable)
        }
    }

    private func deduplicatedIdentifiers(_ identifiers: [String]) -> [String] {
        var seenIdentifiers = Set<String>()
        var deduplicatedIdentifiers: [String] = []
        for identifier in identifiers {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentifier.isEmpty, !seenIdentifiers.contains(trimmedIdentifier) else { continue }
            deduplicatedIdentifiers.append(trimmedIdentifier)
            seenIdentifiers.insert(trimmedIdentifier)
        }
        return deduplicatedIdentifiers
    }

    private func addAssetsToAlbum(_ assets: [PHAsset],
                                  missingIdentifierCount: Int,
                                  completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        guard !assets.isEmpty else {
            completion(.added(addedCount: 0,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: 0))
            return
        }

        addAssetToAlbum(assets,
                        index: 0,
                        missingIdentifierCount: missingIdentifierCount,
                        failedAddCount: 0,
                        completion: completion)
    }

    private func addAssetToAlbum(_ assets: [PHAsset],
                                 index: Int,
                                 missingIdentifierCount: Int,
                                 failedAddCount: Int,
                                 completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        guard index < assets.count else {
            completion(.added(addedCount: assets.count - failedAddCount,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: failedAddCount))
            return
        }

        photoManager.addToPhotosWallpaperAlbum(asset: assets[index]) { result in
            let nextFailedAddCount: Int
            switch result {
            case .success:
                nextFailedAddCount = failedAddCount
            case .failure(let error):
                debugLog("CurrentWallpaperAlbumAdder: failed to add current wallpaper \(index + 1) to album: \(error)")
                nextFailedAddCount = failedAddCount + 1
            }
            addAssetToAlbum(assets,
                            index: index + 1,
                            missingIdentifierCount: missingIdentifierCount,
                            failedAddCount: nextFailedAddCount,
                            completion: completion)
        }
    }
}

final class CurrentWallpaperAlbumController {
    private let historyLogger: WallpaperHistoryLogger
    private let photoManager: PhotoManaging
    private let notifier: WallpaperCycleNotifying

    init(historyLogger: WallpaperHistoryLogger,
         photoManager: PhotoManaging = PhotoManager.shared,
         notifier: WallpaperCycleNotifying = UserNotificationWallpaperCycleNotifier()) {
        self.historyLogger = historyLogger
        self.photoManager = photoManager
        self.notifier = notifier
    }

    func addCurrentWallpapersToAlbum() {
        let identifiers = historyLogger.currentWallpaperIdentifiersSnapshot()
        CurrentWallpaperAlbumAdder(photoManager: photoManager).addWallpapers(withLocalIdentifiers: identifiers) { [weak self] result in
            DispatchQueue.main.async {
                self?.handle(result)
            }
        }
    }

    private func handle(_ result: CurrentWallpaperAlbumAdditionResult) {
        switch result {
        case .added(let addedCount, let missingIdentifierCount, let failedAddCount):
            if addedCount > 0, missingIdentifierCount == 0, failedAddCount == 0 {
                notifier.notifyCurrentWallpapersAddedToAlbum(count: addedCount)
                return
            }
            showAlert(title: "Some Wallpapers Could Not Be Added",
                      message: albumSummary(addedCount: addedCount,
                                            missingIdentifierCount: missingIdentifierCount,
                                            failedAddCount: failedAddCount))
        case .noRememberedWallpapers:
            showAlert(title: "No Current Wallpapers Yet",
                      message: "Photos Wallpaper can’t add current wallpapers to the album until it has set the wallpaper at least once since startup.")
        case .waitingForAuthorization:
            showAlert(title: "Photos Access Needed",
                      message: "Photos Wallpaper is waiting for permission to read your Photos library. Try again after approving access.")
        case .permissionDenied:
            showAlert(title: "Photos Access Needed",
                      message: "Enable Photos access in System Settings > Privacy & Security > Photos, then try again.")
        case .unavailable:
            showAlert(title: "Photos Unavailable",
                      message: "Photos Wallpaper could not search your Photos library right now.")
        }
    }

    private func albumSummary(addedCount: Int, missingIdentifierCount: Int, failedAddCount: Int) -> String {
        var parts: [String] = []
        parts.append("Added \(addedCount) wallpaper photo\(addedCount == 1 ? "" : "s") to the Photos Wallpaper album.")
        if missingIdentifierCount > 0 {
            parts.append("\(missingIdentifierCount) remembered wallpaper photo\(missingIdentifierCount == 1 ? "" : "s") could not be found in Photos.")
        }
        if failedAddCount > 0 {
            parts.append("\(failedAddCount) wallpaper photo\(failedAddCount == 1 ? "" : "s") could not be added.")
        }
        return parts.joined(separator: " ")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
