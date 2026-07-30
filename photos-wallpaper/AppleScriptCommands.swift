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
        currentWallpaperAlbumController.addCurrentSessionWallpapersToAlbum(completion: completion)
        return true
    }
}

struct AddCurrentWallpaperScriptResponse: Equatable {
    let result: String?
    let errorNumber: Int
    let errorMessage: String?

    init(additionResult: CurrentWallpaperAlbumAdditionResult) {
        let presentation = CurrentWallpaperAlbumResultPresenter.scriptPresentation(for: additionResult)
        switch additionResult {
        case .added(_, _, let missingIdentifierCount, let failedAddCount)
            where missingIdentifierCount == 0 && failedAddCount == 0:
            result = presentation.combinedMessage
            errorNumber = NSNoScriptError
            errorMessage = nil
        case .noWallpaperSetThisSession:
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

        let didStart = AppleScriptCommandCoordinator.shared.addCurrentWallpapersToPhotosWallpaperAlbum { [self] result in
            debugLog("AddCurrentWallpaperToPhotosWallpaperAlbumCommand: album request completed with \(result).")
            let response = AddCurrentWallpaperScriptResponse(additionResult: result)
            resumeExecutionOnNextMainQueueTurn(
                withResult: response.result,
                errorNumber: response.errorNumber,
                errorMessage: response.errorMessage)
        }

        guard didStart else {
            debugLog("AddCurrentWallpaperToPhotosWallpaperAlbumCommand: album controller was not ready.")
            resumeExecutionOnNextMainQueueTurn(
                withResult: nil,
                errorNumber: NSInternalScriptError,
                errorMessage: "Photos Wallpaper is not ready to add the current wallpaper.")
            return nil
        }

        return nil
    }

    private func resumeExecutionOnNextMainQueueTurn(
        withResult result: Any?,
        errorNumber: Int,
        errorMessage: String?
    ) {
        // Cocoa scripting requires the command handler to return before a suspended command is
        // resumed. Some album-result paths complete synchronously, so always defer the reply.
        DispatchQueue.main.async { [self] in
            scriptErrorNumber = errorNumber
            scriptErrorString = errorMessage
            resumeExecution(withResult: result)
        }
    }
}
