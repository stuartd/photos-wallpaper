import AppKit
import Combine
import Photos

enum CurrentWallpaperAlbumAdditionResult: Equatable {
    case added(addedCount: Int, alreadyInAlbumCount: Int, missingIdentifierCount: Int, failedAddCount: Int)
    case noRememberedWallpapers
    case noWallpaperSetThisSession
    case waitingForAuthorization
    case permissionDenied
    case unavailable

    var logDescription: String {
        switch self {
        case .added(let addedCount, let alreadyInAlbumCount, let missingIdentifierCount, let failedAddCount):
            return "added: \(addedCount), already in album: \(alreadyInAlbumCount), missing: \(missingIdentifierCount), failed: \(failedAddCount)"
        case .noRememberedWallpapers:
            return "no current wallpapers set by Photos Wallpaper"
        case .noWallpaperSetThisSession:
            return "no wallpaper set in this session"
        case .waitingForAuthorization:
            return "waiting for Photos authorization"
        case .permissionDenied:
            return "Photos permission denied"
        case .unavailable:
            return "Photos unavailable"
        }
    }
}

enum CurrentWallpaperAlbumAlertAction: Equatable {
    case done
    case openAlbum
    case openPhotos
}

struct CurrentWallpaperAlbumResultPresentation: Equatable {
    let title: String
    let message: String
    let primaryButtonTitle: String?
    let primaryAction: CurrentWallpaperAlbumAlertAction?

    init(title: String,
         message: String,
         primaryButtonTitle: String? = nil,
         primaryAction: CurrentWallpaperAlbumAlertAction? = nil) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
    }

    var combinedMessage: String {
        message.isEmpty ? title : "\(title): \(message)"
    }
}

enum CurrentWallpaperAlbumStrings {
    static let addedTitle = "Added to the Photos Wallpaper album"
    static let alreadyInAlbumTitle = "Already in the Photos Wallpaper album"
    static let openAlbumButtonTitle = "Open Album"

    static let currentWallpaperNotSetTitle = "The current wallpaper was not set by Photos Wallpaper"
    static let currentWallpaperNotSetMessage = "Only wallpapers set by Photos Wallpaper can be added to the album."
    static let noWallpaperSetThisSessionTitle = "No wallpaper set in this session"
    static let noWallpaperSetThisSessionMessage = "Photos Wallpaper has not set a wallpaper since it launched, so there is nothing to add."
    static let photosAccessNeededTitle = "Photos access needed"
    static let waitingForPhotosAccessMessage = "Approve the Photos access request to continue."
    static let photosAccessDeniedMessage = "Enable Photos access in System Settings > Privacy & Security > Photos, then try again."
    static let photosUnavailableTitle = "Photos unavailable"
    static let photosUnavailableMessage = "Photos Wallpaper could not search your Photos library right now."

    static let singlePhotoRediscoveryMessage = "In the album, right-click the wallpaper photo and choose Show in All Photos to see the photos around it."
    static let multiplePhotoRediscoveryMessage = "In the album, right-click a wallpaper photo and choose Show in All Photos to see the photos around it."
    static let noPhotosAddedMessage = "No wallpaper photos were added to the Photos Wallpaper album."
    static let singlePhotoAddedMessage = "Added the wallpaper photo to the Photos Wallpaper album."
    static let twoPhotosAddedMessage = "Added both wallpaper photos to the Photos Wallpaper album."
    static let allPhotosAddedMessage = "Added all wallpaper photos to the Photos Wallpaper album."
    static let singlePhotoAlreadyInAlbumMessage = "The wallpaper photo was already in the Photos Wallpaper album."
    static let twoPhotosAlreadyInAlbumMessage = "Both wallpaper photos were already in the Photos Wallpaper album."
    static let singlePhotoMissingMessage = "One wallpaper photo is no longer in Photos, so it could not be added."
    static let singlePhotoMissingTitle = "Wallpaper photo no longer in Photos"
    static let multiplePhotosMissingTitle = "Wallpaper photos no longer in Photos"
    static let singlePhotoCouldNotBeAddedTitle = "Wallpaper photo could not be added"
    static let somePhotosCouldNotBeAddedTitle = "Some wallpaper photos could not be added"

    static let albumCouldNotBeOpenedTitle = "Album could not be opened"
    static let albumCouldNotBeOpenedMessage = "Open Photos and select Photos Wallpaper under Albums in the sidebar."
    static let openPhotosButtonTitle = "Open Photos"
    static let photosCouldNotBeOpenedTitle = "Photos could not be opened"
    static let photosCouldNotBeOpenedMessage = "Open Photos manually and select Photos Wallpaper under Albums in the sidebar."
    static let doneButtonTitle = "Done"
    static let okButtonTitle = "OK"

    static func rediscoveryMessage(photoCount: Int) -> String {
        photoCount == 1 ? singlePhotoRediscoveryMessage : multiplePhotoRediscoveryMessage
    }

    static func albumSuccessMessage(addedCount: Int) -> String {
        switch addedCount {
        case 1:
            return singlePhotoAddedMessage
        case 2:
            return twoPhotosAddedMessage
        default:
            return allPhotosAddedMessage
        }
    }

    static func albumAlreadyInAlbumMessage(alreadyInAlbumCount: Int) -> String {
        switch alreadyInAlbumCount {
        case 1:
            return singlePhotoAlreadyInAlbumMessage
        case 2:
            return twoPhotosAlreadyInAlbumMessage
        default:
            return "\(alreadyInAlbumCount) wallpaper photos were already in the Photos Wallpaper album."
        }
    }

    static func missingPhotosMessage(missingIdentifierCount: Int) -> String {
        if missingIdentifierCount == 1 {
            return singlePhotoMissingMessage
        }
        return "\(missingIdentifierCount) wallpaper photos are no longer in Photos, so they could not be added."
    }

    static func failedToAddMessage(failedAddCount: Int) -> String {
        "\(failedAddCount) wallpaper photo\(failedAddCount == 1 ? "" : "s") could not be added."
    }

    static func albumFailureTitle(missingIdentifierCount: Int, failedAddCount: Int) -> String {
        if failedAddCount == 0 {
            return missingIdentifierCount == 1 ? singlePhotoMissingTitle : multiplePhotosMissingTitle
        }
        if missingIdentifierCount == 0, failedAddCount == 1 {
            return singlePhotoCouldNotBeAddedTitle
        }
        return somePhotosCouldNotBeAddedTitle
    }
}

enum CurrentWallpaperAlbumResultPresenter {
    static func presentation(for result: CurrentWallpaperAlbumAdditionResult) -> CurrentWallpaperAlbumResultPresentation {
        switch result {
        case .added(let addedCount, let alreadyInAlbumCount, let missingIdentifierCount, let failedAddCount):
            let summary = albumSummary(addedCount: addedCount,
                                       alreadyInAlbumCount: alreadyInAlbumCount,
                                       missingIdentifierCount: missingIdentifierCount,
                                       failedAddCount: failedAddCount)
            let photoCountInAlbum = addedCount + alreadyInAlbumCount
            guard missingIdentifierCount > 0 || failedAddCount > 0 else {
                return CurrentWallpaperAlbumResultPresentation(
                    title: addedCount > 0 ? CurrentWallpaperAlbumStrings.addedTitle : CurrentWallpaperAlbumStrings.alreadyInAlbumTitle,
                    message: CurrentWallpaperAlbumStrings.rediscoveryMessage(photoCount: photoCountInAlbum),
                    primaryButtonTitle: CurrentWallpaperAlbumStrings.openAlbumButtonTitle,
                    primaryAction: .openAlbum)
            }
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.albumFailureTitle(missingIdentifierCount: missingIdentifierCount,
                                                                      failedAddCount: failedAddCount),
                message: summary,
                primaryButtonTitle: photoCountInAlbum > 0 ? CurrentWallpaperAlbumStrings.openAlbumButtonTitle : nil,
                primaryAction: photoCountInAlbum > 0 ? .openAlbum : nil)
        case .noRememberedWallpapers:
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.currentWallpaperNotSetTitle,
                message: CurrentWallpaperAlbumStrings.currentWallpaperNotSetMessage)
        case .noWallpaperSetThisSession:
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.noWallpaperSetThisSessionTitle,
                message: CurrentWallpaperAlbumStrings.noWallpaperSetThisSessionMessage)
        case .waitingForAuthorization:
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.photosAccessNeededTitle,
                message: CurrentWallpaperAlbumStrings.waitingForPhotosAccessMessage)
        case .permissionDenied:
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.photosAccessNeededTitle,
                message: CurrentWallpaperAlbumStrings.photosAccessDeniedMessage)
        case .unavailable:
            return CurrentWallpaperAlbumResultPresentation(
                title: CurrentWallpaperAlbumStrings.photosUnavailableTitle,
                message: CurrentWallpaperAlbumStrings.photosUnavailableMessage)
        }
    }

    static func scriptPresentation(for result: CurrentWallpaperAlbumAdditionResult) -> CurrentWallpaperAlbumResultPresentation {
        guard case .added(let addedCount,
                          let alreadyInAlbumCount,
                          let missingIdentifierCount,
                          let failedAddCount) = result else {
            return presentation(for: result)
        }

        let summary = albumSummary(addedCount: addedCount,
                                   alreadyInAlbumCount: alreadyInAlbumCount,
                                   missingIdentifierCount: missingIdentifierCount,
                                   failedAddCount: failedAddCount)
        guard missingIdentifierCount > 0 || failedAddCount > 0 else {
            return CurrentWallpaperAlbumResultPresentation(title: summary, message: "")
        }
        return CurrentWallpaperAlbumResultPresentation(
            title: CurrentWallpaperAlbumStrings.albumFailureTitle(missingIdentifierCount: missingIdentifierCount,
                                                                  failedAddCount: failedAddCount),
            message: summary)
    }

    private static func albumSummary(addedCount: Int,
                                     alreadyInAlbumCount: Int,
                                     missingIdentifierCount: Int,
                                     failedAddCount: Int) -> String {
        var parts: [String] = []
        if addedCount > 0 {
            parts.append(CurrentWallpaperAlbumStrings.albumSuccessMessage(addedCount: addedCount))
        }
        if alreadyInAlbumCount > 0 {
            parts.append(CurrentWallpaperAlbumStrings.albumAlreadyInAlbumMessage(alreadyInAlbumCount: alreadyInAlbumCount))
        }
        if missingIdentifierCount > 0 {
            parts.append(CurrentWallpaperAlbumStrings.missingPhotosMessage(missingIdentifierCount: missingIdentifierCount))
        }
        if failedAddCount > 0 {
            parts.append(CurrentWallpaperAlbumStrings.failedToAddMessage(failedAddCount: failedAddCount))
        }
        if parts.isEmpty {
            parts.append(CurrentWallpaperAlbumStrings.noPhotosAddedMessage)
        }
        return parts.joined(separator: " ")
    }
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
                              alreadyInAlbumCount: 0,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: 0))
            return
        }

        addAssetToAlbum(assets,
                        index: 0,
                        addedCount: 0,
                        alreadyInAlbumCount: 0,
                        missingIdentifierCount: missingIdentifierCount,
                        failedAddCount: 0,
                        completion: completion)
    }

    private func addAssetToAlbum(_ assets: [PHAsset],
                                 index: Int,
                                 addedCount: Int,
                                 alreadyInAlbumCount: Int,
                                 missingIdentifierCount: Int,
                                 failedAddCount: Int,
                                 completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        guard index < assets.count else {
            completion(.added(addedCount: addedCount,
                              alreadyInAlbumCount: alreadyInAlbumCount,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: failedAddCount))
            return
        }

        photoManager.addToPhotosWallpaperAlbum(asset: assets[index]) { result in
            let nextAddedCount: Int
            let nextAlreadyInAlbumCount: Int
            let nextFailedAddCount: Int
            switch result {
            case .success(.added):
                nextAddedCount = addedCount + 1
                nextAlreadyInAlbumCount = alreadyInAlbumCount
                nextFailedAddCount = failedAddCount
            case .success(.alreadyInAlbum):
                nextAddedCount = addedCount
                nextAlreadyInAlbumCount = alreadyInAlbumCount + 1
                nextFailedAddCount = failedAddCount
            case .failure(let error):
                debugLog("CurrentWallpaperAlbumAdder: failed to add current wallpaper \(index + 1) to the Photos Wallpaper album: \(error).")
                nextAddedCount = addedCount
                nextAlreadyInAlbumCount = alreadyInAlbumCount
                nextFailedAddCount = failedAddCount + 1
            }
            addAssetToAlbum(assets,
                            index: index + 1,
                            addedCount: nextAddedCount,
                            alreadyInAlbumCount: nextAlreadyInAlbumCount,
                            missingIdentifierCount: missingIdentifierCount,
                            failedAddCount: nextFailedAddCount,
                            completion: completion)
        }
    }
}

@MainActor final class CurrentWallpaperAlbumController: ObservableObject {
    @Published private(set) var isPresentingAlert = false
    @Published private(set) var isWaitingForAuthorization = false

    private let historyLogger: WallpaperHistoryLogger
    private let photoManager: PhotoManaging
    private let albumOpener: PhotosAlbumOpening
    private let showAlert: @MainActor (CurrentWallpaperAlbumResultPresentation) -> CurrentWallpaperAlbumAlertAction
    private var pendingAuthorizationRequests: [PendingAuthorizationRequest] = []

    private struct PendingAuthorizationRequest {
        let identifiers: [String]
        let showsResultAlert: Bool
        let completion: (@MainActor (CurrentWallpaperAlbumAdditionResult) -> Void)?
    }

    convenience init(historyLogger: WallpaperHistoryLogger) {
        self.init(historyLogger: historyLogger,
                  photoManager: PhotoManager.shared,
                  albumOpener: AppKitPhotosAlbumOpener(),
                  showAlert: CurrentWallpaperAlbumController.runModalAlert)
    }

    convenience init(
        historyLogger: WallpaperHistoryLogger,
        photoManager: PhotoManaging,
        showAlert: @escaping @MainActor (CurrentWallpaperAlbumResultPresentation) -> CurrentWallpaperAlbumAlertAction
    ) {
        self.init(historyLogger: historyLogger,
                  photoManager: photoManager,
                  albumOpener: AppKitPhotosAlbumOpener(),
                  showAlert: showAlert)
    }

    init(historyLogger: WallpaperHistoryLogger,
         photoManager: PhotoManaging,
         albumOpener: PhotosAlbumOpening,
         showAlert: @escaping @MainActor (CurrentWallpaperAlbumResultPresentation) -> CurrentWallpaperAlbumAlertAction) {
        self.historyLogger = historyLogger
        self.photoManager = photoManager
        self.albumOpener = albumOpener
        self.showAlert = showAlert
        photoManager.addPhotoAuthorizationChangeHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.retryPendingAuthorizationRequests()
            }
        }
    }

    func addCurrentWallpapersToAlbum(
        showsResultAlert: Bool = true,
        completion: (@MainActor (CurrentWallpaperAlbumAdditionResult) -> Void)? = nil
    ) {
        let identifiers = currentManagedWallpaperIdentifiers()
        addWallpapersToAlbum(withLocalIdentifiers: identifiers,
                            showsResultAlert: showsResultAlert,
                            completion: completion)
    }

    func addCurrentSessionWallpapersToAlbum(
        completion: @escaping @MainActor (CurrentWallpaperAlbumAdditionResult) -> Void
    ) {
        let identifiers = historyLogger.currentSessionWallpaperIdentifiersSnapshot()
        guard !identifiers.isEmpty else {
            completion(.noWallpaperSetThisSession)
            return
        }

        addWallpapersToAlbum(withLocalIdentifiers: identifiersStillCurrent(identifiers),
                            showsResultAlert: false,
                            completion: completion)
    }

    private func currentManagedWallpaperIdentifiers() -> [String] {
        photoManager.managedCurrentWallpaperIdentifiers()
    }

    private func identifiersStillCurrent(_ identifiers: [String]) -> [String] {
        let currentIdentifiers = Set(currentManagedWallpaperIdentifiers())
        return identifiers.filter { currentIdentifiers.contains($0) }
    }

    private func addWallpapersToAlbum(
        withLocalIdentifiers identifiers: [String],
        showsResultAlert: Bool,
        completion: (@MainActor (CurrentWallpaperAlbumAdditionResult) -> Void)?
    ) {
        CurrentWallpaperAlbumAdder(photoManager: photoManager).addWallpapers(withLocalIdentifiers: identifiers) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    completion?(.unavailable)
                    return
                }
                guard result != .waitingForAuthorization else {
                    self.pendingAuthorizationRequests.append(
                        PendingAuthorizationRequest(identifiers: identifiers,
                                                    showsResultAlert: showsResultAlert,
                                                    completion: completion))
                    self.isWaitingForAuthorization = true
                    debugLog("CurrentWallpaperAlbumController: waiting for Photos authorization before retrying album request.")
                    return
                }
                if showsResultAlert {
                    self.handle(result)
                }
                completion?(result)
            }
        }
    }

    private func retryPendingAuthorizationRequests() {
        let requests = pendingAuthorizationRequests
        pendingAuthorizationRequests.removeAll()
        isWaitingForAuthorization = false
        guard !requests.isEmpty else { return }

        debugLog("CurrentWallpaperAlbumController: retrying \(requests.count) album request(s) after Photos authorization changed.")
        for request in requests {
            addWallpapersToAlbum(withLocalIdentifiers: identifiersStillCurrent(request.identifiers),
                                showsResultAlert: request.showsResultAlert,
                                completion: request.completion)
        }
    }

    private func handle(_ result: CurrentWallpaperAlbumAdditionResult) {
        let presentation = CurrentWallpaperAlbumResultPresenter.presentation(for: result)
        switch presentAlert(presentation) {
        case .openAlbum:
            openPhotosWallpaperAlbum()
        case .openPhotos:
            openPhotosApplication()
        case .done:
            break
        }
    }

    private func openPhotosWallpaperAlbum() {
        guard !albumOpener.openPhotosWallpaperAlbum() else { return }

        let fallback = CurrentWallpaperAlbumResultPresentation(
            title: CurrentWallpaperAlbumStrings.albumCouldNotBeOpenedTitle,
            message: CurrentWallpaperAlbumStrings.albumCouldNotBeOpenedMessage,
            primaryButtonTitle: CurrentWallpaperAlbumStrings.openPhotosButtonTitle,
            primaryAction: .openPhotos)
        if presentAlert(fallback) == .openPhotos {
            openPhotosApplication()
        }
    }

    private func openPhotosApplication() {
        guard !albumOpener.openPhotosApplication() else { return }

        _ = presentAlert(CurrentWallpaperAlbumResultPresentation(
            title: CurrentWallpaperAlbumStrings.photosCouldNotBeOpenedTitle,
            message: CurrentWallpaperAlbumStrings.photosCouldNotBeOpenedMessage))
    }

    private func presentAlert(_ presentation: CurrentWallpaperAlbumResultPresentation) -> CurrentWallpaperAlbumAlertAction {
        isPresentingAlert = true
        defer { isPresentingAlert = false }
        return showAlert(presentation)
    }

    private static func runModalAlert(_ presentation: CurrentWallpaperAlbumResultPresentation) -> CurrentWallpaperAlbumAlertAction {
        let alert = NSAlert()
        alert.messageText = presentation.title
        if !presentation.message.isEmpty {
            alert.informativeText = presentation.message
        }

        if let primaryButtonTitle = presentation.primaryButtonTitle,
           let primaryAction = presentation.primaryAction {
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: CurrentWallpaperAlbumStrings.doneButtonTitle)
            return alert.runModal() == .alertFirstButtonReturn ? primaryAction : .done
        }

        alert.addButton(withTitle: CurrentWallpaperAlbumStrings.okButtonTitle)
        _ = alert.runModal()
        return .done
    }
}
