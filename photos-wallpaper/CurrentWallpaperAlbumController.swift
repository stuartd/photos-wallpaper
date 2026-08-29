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
                    title: addedCount > 0 ? "Added to Photos Wallpaper" : "Already in Photos Wallpaper",
                    message: rediscoveryMessage(photoCount: photoCountInAlbum),
                    primaryButtonTitle: "Open Album",
                    primaryAction: .openAlbum)
            }
            return CurrentWallpaperAlbumResultPresentation(
                title: albumFailureTitle(missingIdentifierCount: missingIdentifierCount,
                                         failedAddCount: failedAddCount),
                message: summary,
                primaryButtonTitle: photoCountInAlbum > 0 ? "Open Album" : nil,
                primaryAction: photoCountInAlbum > 0 ? .openAlbum : nil)
        case .noRememberedWallpapers:
            return CurrentWallpaperAlbumResultPresentation(
                title: "Current Wallpaper Not Set by Photos Wallpaper",
                message: "Photos Wallpaper can only add a wallpaper that it set. Choose Change Wallpaper Now, then try again.")
        case .noWallpaperSetThisSession:
            return CurrentWallpaperAlbumResultPresentation(
                title: "No Wallpaper Set This Session",
                message: "Photos Wallpaper can’t run this script until it has set the wallpaper at least once since startup.")
        case .waitingForAuthorization:
            return CurrentWallpaperAlbumResultPresentation(
                title: "Photos Access Needed",
                message: "Photos Wallpaper is waiting for permission to read your Photos library. Try again after approving access.")
        case .permissionDenied:
            return CurrentWallpaperAlbumResultPresentation(
                title: "Photos Access Needed",
                message: "Enable Photos access in System Settings > Privacy & Security > Photos, then try again.")
        case .unavailable:
            return CurrentWallpaperAlbumResultPresentation(
                title: "Photos Unavailable",
                message: "Photos Wallpaper could not search your Photos library right now.")
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
            title: albumFailureTitle(missingIdentifierCount: missingIdentifierCount,
                                     failedAddCount: failedAddCount),
            message: summary)
    }

    private static func rediscoveryMessage(photoCount: Int) -> String {
        if photoCount == 1 {
            return "Open the album in Photos to see the original and rediscover the moment around it."
        }
        return "Open the album in Photos to see the originals and rediscover the moments around them."
    }

    private static func albumSummary(addedCount: Int,
                                     alreadyInAlbumCount: Int,
                                     missingIdentifierCount: Int,
                                     failedAddCount: Int) -> String {
        var parts: [String] = []
        if addedCount > 0 {
            parts.append(albumSuccessMessage(addedCount: addedCount))
        }
        if alreadyInAlbumCount > 0 {
            parts.append(albumAlreadyInAlbumMessage(alreadyInAlbumCount: alreadyInAlbumCount))
        }
        if missingIdentifierCount > 0 {
            parts.append(missingPhotosMessage(missingIdentifierCount: missingIdentifierCount))
        }
        if failedAddCount > 0 {
            parts.append("\(failedAddCount) wallpaper photo\(failedAddCount == 1 ? "" : "s") could not be added.")
        }
        if parts.isEmpty {
            parts.append("No wallpaper photos were added to the Photos Wallpaper album.")
        }
        return parts.joined(separator: " ")
    }

    private static func albumSuccessMessage(addedCount: Int) -> String {
        switch addedCount {
        case 1:
            return "Added the wallpaper photo to the Photos Wallpaper album."
        case 2:
            return "Added both wallpaper photos to the Photos Wallpaper album."
        default:
            return "Added all wallpaper photos to the Photos Wallpaper album."
        }
    }

    private static func albumAlreadyInAlbumMessage(alreadyInAlbumCount: Int) -> String {
        switch alreadyInAlbumCount {
        case 1:
            return "The wallpaper photo was already in the Photos Wallpaper album."
        case 2:
            return "Both wallpaper photos were already in the Photos Wallpaper album."
        default:
            return "\(alreadyInAlbumCount) wallpaper photos were already in the Photos Wallpaper album."
        }
    }

    private static func missingPhotosMessage(missingIdentifierCount: Int) -> String {
        switch missingIdentifierCount {
        case 1:
            return "One wallpaper photo is no longer in Photos, so it could not be added."
        default:
            return "\(missingIdentifierCount) wallpaper photos are no longer in Photos, so they could not be added."
        }
    }

    private static func albumFailureTitle(missingIdentifierCount: Int, failedAddCount: Int) -> String {
        if failedAddCount == 0 {
            switch missingIdentifierCount {
            case 1:
                return "Wallpaper Photo No Longer in Photos"
            default:
                return "Wallpaper Photos No Longer in Photos"
            }
        }

        if missingIdentifierCount == 0, failedAddCount == 1 {
            return "Wallpaper Photo Could Not Be Added"
        }

        return "Some Wallpaper Photos Could Not Be Added"
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
                debugLog("CurrentWallpaperAlbumAdder: failed to add current wallpaper \(index + 1) to album: \(error)")
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
            title: "Album Could Not Be Opened",
            message: "Open Photos and select Photos Wallpaper under Albums in the sidebar.",
            primaryButtonTitle: "Open Photos",
            primaryAction: .openPhotos)
        if presentAlert(fallback) == .openPhotos {
            openPhotosApplication()
        }
    }

    private func openPhotosApplication() {
        guard !albumOpener.openPhotosApplication() else { return }

        _ = presentAlert(CurrentWallpaperAlbumResultPresentation(
            title: "Photos Could Not Be Opened",
            message: "Open Photos manually and select Photos Wallpaper under Albums in the sidebar."))
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
            alert.addButton(withTitle: "Done")
            return alert.runModal() == .alertFirstButtonReturn ? primaryAction : .done
        }

        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
        return .done
    }
}
