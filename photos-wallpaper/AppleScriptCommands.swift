import Foundation

@MainActor
final class AppleScriptCommandCoordinator {
    static let shared = AppleScriptCommandCoordinator()

    private weak var currentWallpaperAlbumController: CurrentWallpaperAlbumController?

    func configure(currentWallpaperAlbumController: CurrentWallpaperAlbumController) {
        self.currentWallpaperAlbumController = currentWallpaperAlbumController
    }

    @discardableResult
    func addCurrentWallpapersToPhotosWallpaperAlbum(
        completion: @escaping @MainActor (CurrentWallpaperAlbumAdditionResult) -> Void
    ) -> Bool {
        guard let currentWallpaperAlbumController else { return false }
        currentWallpaperAlbumController.addCurrentWallpapersToAlbum(
            showsResultAlert: false,
            completion: completion)
        return true
    }
}

struct AddCurrentWallpaperScriptResponse: Equatable {
    let result: String?
    let errorNumber: Int
    let errorMessage: String?

    init(additionResult: CurrentWallpaperAlbumAdditionResult) {
        let presentation = CurrentWallpaperAlbumResultPresenter.presentation(for: additionResult)
        switch additionResult {
        case .added(_, _, let missingIdentifierCount, let failedAddCount)
            where missingIdentifierCount == 0 && failedAddCount == 0:
            result = presentation.combinedMessage
            errorNumber = NSNoScriptError
            errorMessage = nil
        default:
            result = nil
            errorNumber = NSInternalScriptError
            errorMessage = presentation.combinedMessage
        }
    }
}

@objc(AddCurrentWallpaperToPhotosWallpaperAlbumCommand)
final class AddCurrentWallpaperToPhotosWallpaperAlbumCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        debugLog("AddCurrentWallpaperToPhotosWallpaperAlbumCommand: received AppleScript album request.")
        suspendExecution()

        let didStart = AppleScriptCommandCoordinator.shared.addCurrentWallpapersToPhotosWallpaperAlbum { [weak self] result in
            guard let self else { return }
            debugLog("AddCurrentWallpaperToPhotosWallpaperAlbumCommand: album request completed with \(result).")
            let response = AddCurrentWallpaperScriptResponse(additionResult: result)
            self.scriptErrorNumber = response.errorNumber
            self.scriptErrorString = response.errorMessage
            self.resumeExecution(withResult: response.result)
        }

        guard didStart else {
            debugLog("AddCurrentWallpaperToPhotosWallpaperAlbumCommand: album controller was not ready.")
            scriptErrorNumber = NSInternalScriptError
            scriptErrorString = "Photos Wallpaper is not ready to add the current wallpaper."
            resumeExecution(withResult: nil)
            return nil
        }

        return nil
    }
}
