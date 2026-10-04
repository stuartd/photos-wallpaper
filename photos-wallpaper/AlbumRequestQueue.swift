import Foundation

/// Serializes mutations across all menu and scripting callers, including album creation.
@MainActor
final class AlbumRequestQueue {
    typealias ResultHandler = (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void
    private var pending: [(@escaping ResultHandler) -> Void] = []
    private var isRunning = false

    func enqueue(operation: @escaping (@escaping ResultHandler) -> Void,
                 completion: @escaping ResultHandler) {
        pending.append { finish in
            var hasCompleted = false
            operation { result in
                guard !hasCompleted else { return }
                hasCompleted = true
                completion(result)
                finish(result)
            }
        }
        startNext()
    }

    private func startNext() {
        guard !isRunning, !pending.isEmpty else { return }
        isRunning = true
        let operation = pending.removeFirst()
        var completed = false
        operation { [self] _ in
            guard !completed else { return }
            completed = true
            isRunning = false
            startNext()
        }
    }
}

enum AlbumMutationOutcome {
    static func result(transactionSucceeded: Bool, requestCreated: Bool,
                       containsAsset: Bool, error: Error?) -> Result<PhotosWallpaperAlbumAddResult, Error> {
        guard transactionSucceeded, requestCreated, containsAsset, error == nil else {
            return .failure(error ?? PhotosWallpaperAlbumError.assetCouldNotBeAdded)
        }
        return .success(.added)
    }
}
