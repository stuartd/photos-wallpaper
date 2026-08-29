import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func currentWallpaperAlbumAdderAddsDeduplicatedCurrentWallpapersWithoutChangingWallpaper() {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset])
        let adder = CurrentWallpaperAlbumAdder(photoManager: photoManager)
        var result: CurrentWallpaperAlbumAdditionResult?

        adder.addWallpapers(withLocalIdentifiers: [" FIRST-ID/L0/001 ", "FIRST-ID/L0/001", "SECOND-ID/L0/001"]) {
            result = $0
        }

        #expect(result == .added(addedCount: 2, alreadyInAlbumCount: 0, missingIdentifierCount: 0, failedAddCount: 0))
        #expect(photoManager.batchLookupRequests == [["FIRST-ID/L0/001", "SECOND-ID/L0/001"]])
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [ObjectIdentifier(firstAsset), ObjectIdentifier(secondAsset)])
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func currentWallpaperAlbumAdderReportsMissingPhotosAndAddFailures() {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset])
        photoManager.missingLookupIdentifiers = ["MISSING-ID/L0/001"]
        photoManager.albumAddResults = [
            .success(.added),
            .failure(TestError.expectedFailure)
        ]
        let adder = CurrentWallpaperAlbumAdder(photoManager: photoManager)
        var result: CurrentWallpaperAlbumAdditionResult?

        adder.addWallpapers(withLocalIdentifiers: ["FIRST-ID/L0/001", "MISSING-ID/L0/001", "SECOND-ID/L0/001"]) {
            result = $0
        }

        #expect(result == .added(addedCount: 1, alreadyInAlbumCount: 0, missingIdentifierCount: 1, failedAddCount: 1))
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [ObjectIdentifier(firstAsset), ObjectIdentifier(secondAsset)])
    }

    @Test func currentWallpaperAlbumAdderReportsAlreadyAddedPhotos() {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset])
        photoManager.albumAddResults = [
            .success(.alreadyInAlbum),
            .success(.added)
        ]
        let adder = CurrentWallpaperAlbumAdder(photoManager: photoManager)
        var result: CurrentWallpaperAlbumAdditionResult?

        adder.addWallpapers(withLocalIdentifiers: ["FIRST-ID/L0/001", "SECOND-ID/L0/001"]) {
            result = $0
        }

        #expect(result == .added(addedCount: 1, alreadyInAlbumCount: 1, missingIdentifierCount: 0, failedAddCount: 0))
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [ObjectIdentifier(firstAsset), ObjectIdentifier(secondAsset)])
    }

    @Test func currentWallpaperAlbumAdderDoesNotSearchPhotosWhenThereAreNoRememberedWallpapers() {
        let photoManager = FakePhotoManager()
        let adder = CurrentWallpaperAlbumAdder(photoManager: photoManager)
        var result: CurrentWallpaperAlbumAdditionResult?

        adder.addWallpapers(withLocalIdentifiers: [" ", "\n"]) {
            result = $0
        }

        #expect(result == .noRememberedWallpapers)
        #expect(photoManager.batchLookupRequests.isEmpty)
        #expect(photoManager.albumAddRequests.isEmpty)
    }

    @Test func currentWallpaperAlbumAdderPropagatesPhotosLookupFailures() {
        let photoManager = FakePhotoManager()
        let adder = CurrentWallpaperAlbumAdder(photoManager: photoManager)

        photoManager.photoLookupOverride = .waitingForAuthorization
        adder.addWallpapers(withLocalIdentifiers: ["FIRST-ID/L0/001"]) { result in
            #expect(result == .waitingForAuthorization)
        }

        photoManager.photoLookupOverride = .permissionDenied
        adder.addWallpapers(withLocalIdentifiers: ["FIRST-ID/L0/001"]) { result in
            #expect(result == .permissionDenied)
        }

        photoManager.photoLookupOverride = .unavailable
        adder.addWallpapers(withLocalIdentifiers: ["FIRST-ID/L0/001"]) { result in
            #expect(result == .unavailable)
        }
    }

    @Test func currentWallpaperAlbumControllerShowsSingleWallpaperConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1)

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.addedTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.singlePhotoRediscoveryMessage)
        #expect(result.alerts.first?.primaryButtonTitle == CurrentWallpaperAlbumStrings.openAlbumButtonTitle)
        #expect(result.alerts.first?.primaryAction == .openAlbum)
    }

    @Test func currentWallpaperAlbumControllerShowsTwoWallpaperConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 2)

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.addedTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.multiplePhotoRediscoveryMessage)
    }

    @Test func currentWallpaperAlbumControllerShowsThreeOrMoreWallpaperConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 3)

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.addedTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.multiplePhotoRediscoveryMessage)
    }

    @Test func currentWallpaperAlbumControllerShowsAlreadyInAlbumConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1,
                                                             albumAddResults: [.success(.alreadyInAlbum)])

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.alreadyInAlbumTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.singlePhotoRediscoveryMessage)
    }

    @Test func currentWallpaperAlbumControllerDoesNotUseStaleIdentifierAfterWallpaperWasReplaced() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager(assetsToReturn: [makeFakeAsset()])
        photoManager.managedWallpaperIdentifiers = []
        var alerts: [(title: String, message: String)] = []
        let controller = CurrentWallpaperAlbumController(
            historyLogger: logger,
            photoManager: photoManager) { presentation in
                alerts.append((presentation.title, presentation.message))
                return .done
            }
        logger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: STALE-ID/L0/001",
            screenName: "Screen 1",
            screenCount: 1,
            timestamp: Date(timeIntervalSince1970: 0))

        controller.addCurrentWallpapersToAlbum()
        let didShowExplanation = await waitForCondition {
            !alerts.isEmpty
        }

        #expect(didShowExplanation)
        #expect(alerts.first?.title == CurrentWallpaperAlbumStrings.currentWallpaperNotSetTitle)
        #expect(alerts.first?.message == CurrentWallpaperAlbumStrings.currentWallpaperNotSetMessage)
        #expect(photoManager.batchLookupRequests.isEmpty)
        #expect(photoManager.albumAddRequests.isEmpty)
    }

    @Test func currentWallpaperAlbumControllerUsesIdentifierFromCurrentWallpaperFile() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let asset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [asset])
        photoManager.managedWallpaperIdentifiers = ["CURRENT-ID/L0/001"]
        var alerts: [(title: String, message: String)] = []
        let controller = CurrentWallpaperAlbumController(
            historyLogger: logger,
            photoManager: photoManager) { presentation in
                alerts.append((presentation.title, presentation.message))
                return .done
            }
        let timestamp = Date(timeIntervalSince1970: 0)
        logger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: REPLACED-ID/L0/001",
            screenName: "Screen 1",
            screenCount: 2,
            timestamp: timestamp)
        logger.recordWallpaperChange(
            photoName: "IMG_0002.HEIC created 1 Jan 2024 at 12:00:00, id: CURRENT-ID/L0/001",
            screenName: "Screen 2",
            screenCount: 2,
            timestamp: timestamp)

        controller.addCurrentWallpapersToAlbum()
        let didShowConfirmation = await waitForCondition {
            !alerts.isEmpty
        }

        #expect(didShowConfirmation)
        #expect(photoManager.batchLookupRequests == [["CURRENT-ID/L0/001"]])
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [ObjectIdentifier(asset)])
    }

    @Test func generatedWallpaperURLMustBeInsideTheWallpaperCache() {
        let cacheURL = URL(fileURLWithPath: "/tmp/photos-wallpaper/.WallpaperCache", isDirectory: true)

        #expect(PhotoManager.isGeneratedWallpaperURL(
            cacheURL.appendingPathComponent("current-wallpaper-1-ABC.jpg"),
            in: cacheURL))
        #expect(!PhotoManager.isGeneratedWallpaperURL(
            URL(fileURLWithPath: "/tmp/current-wallpaper-1-ABC.jpg"),
            in: cacheURL))
        #expect(!PhotoManager.isGeneratedWallpaperURL(
            cacheURL.appendingPathComponent("ordinary-wallpaper.jpg"),
            in: cacheURL))
    }

    @Test func generatedWallpaperFilenameCarriesItsPhotosIdentifier() {
        let cacheURL = URL(fileURLWithPath: "/tmp/photos-wallpaper/.WallpaperCache", isDirectory: true)
        let identifier = "A43F0D8A-4F5A-47A3-AF9D-03B54BD21D9C/L0/001"
        let encodedIdentifier = Data(identifier.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let wallpaperURL = cacheURL.appendingPathComponent(
            "current-wallpaper-42-ABC.asset-\(encodedIdentifier).jpg")

        #expect(PhotoManager.localIdentifier(inGeneratedWallpaperURL: wallpaperURL,
                                             in: cacheURL) == identifier)
        #expect(PhotoManager.localIdentifier(
            inGeneratedWallpaperURL: cacheURL.appendingPathComponent("current-wallpaper-42-ABC.jpg"),
            in: cacheURL) == nil)
        #expect(PhotoManager.localIdentifier(
            inGeneratedWallpaperURL: URL(fileURLWithPath: "/tmp/\(wallpaperURL.lastPathComponent)"),
            in: cacheURL) == nil)
    }

    @Test func currentWallpaperAlbumControllerShowsMixedAddedAndAlreadyInAlbumConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 2,
                                                             albumAddResults: [.success(.added), .success(.alreadyInAlbum)])

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.addedTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.multiplePhotoRediscoveryMessage)
    }

    @Test func currentWallpaperAlbumControllerExplainsMissingPhotosInPlainLanguage() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1,
                                                             missingLookupIdentifiers: ["ID-1/L0/001"],
                                                             expectedAlbumAddCount: 0)

        #expect(result.alerts.first?.title == CurrentWallpaperAlbumStrings.singlePhotoMissingTitle)
        #expect(result.alerts.first?.message == CurrentWallpaperAlbumStrings.singlePhotoMissingMessage)
        #expect(result.alerts.first?.primaryAction == nil)
    }

    @Test func currentWallpaperAlbumControllerOpensAlbumAfterConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1,
                                                             alertActions: [.openAlbum])

        #expect(result.albumOpener.openAlbumCallCount == 1)
        #expect(result.albumOpener.openPhotosCallCount == 0)
    }

    @Test func currentWallpaperAlbumControllerFallsBackWhenAlbumCannotBeOpened() async {
        let result = await currentWallpaperAlbumConfirmation(
            assetCount: 1,
            alertActions: [.openAlbum, .openPhotos],
            albumOpenResult: false)

        #expect(result.alerts.count == 2)
        #expect(result.alerts.last?.title == CurrentWallpaperAlbumStrings.albumCouldNotBeOpenedTitle)
        #expect(result.alerts.last?.message == CurrentWallpaperAlbumStrings.albumCouldNotBeOpenedMessage)
        #expect(result.alerts.last?.primaryButtonTitle == CurrentWallpaperAlbumStrings.openPhotosButtonTitle)
        #expect(result.alerts.last?.primaryAction == .openPhotos)
        #expect(result.albumOpener.openAlbumCallCount == 1)
        #expect(result.albumOpener.openPhotosCallCount == 1)
    }

    @Test func photosAlbumOpenerTargetsThePhotosWallpaperAlbum() {
        var executedScripts: [String] = []
        var openPhotosCallCount = 0
        let opener = AppKitPhotosAlbumOpener(
            runAppleScript: { source in
                executedScripts.append(source)
                return true
            },
            openApplication: {
                openPhotosCallCount += 1
                return true
            })

        #expect(opener.openPhotosWallpaperAlbum())
        #expect(executedScripts.count == 1)
        #expect(executedScripts[0].contains("tell application \"/System/Applications/Photos.app\""))
        #expect(executedScripts[0].contains("every album whose name is \"Photos Wallpaper\""))
        #expect(executedScripts[0].contains("spotlight item 1 of matchingAlbums"))
        #expect(openPhotosCallCount == 0)

        #expect(opener.openPhotosApplication())
        #expect(openPhotosCallCount == 1)
    }

    @Test func currentWallpaperAlbumControllerRetriesAfterPhotosAuthorizationIsGranted() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager(assetsToReturn: [makeFakeAsset()])
        photoManager.managedWallpaperIdentifiers = ["ID-1/L0/001"]
        photoManager.photoLookupOverride = .waitingForAuthorization
        var alerts: [CurrentWallpaperAlbumResultPresentation] = []
        let controller = CurrentWallpaperAlbumController(
            historyLogger: logger,
            photoManager: photoManager) { presentation in
                alerts.append(presentation)
                return .done
            }
        logger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: ID-1/L0/001",
            screenName: "Screen 1",
            screenCount: 1,
            timestamp: Date(timeIntervalSince1970: 0))

        controller.addCurrentWallpapersToAlbum()
        let didStartWaiting = await waitForCondition {
            controller.isWaitingForAuthorization
        }

        #expect(didStartWaiting)
        #expect(alerts.isEmpty)
        #expect(photoManager.batchLookupRequests == [["ID-1/L0/001"]])
        #expect(photoManager.albumAddRequests.isEmpty)

        photoManager.photoLookupOverride = nil
        photoManager.notifyPhotoAuthorizationDidChange()
        let didShowConfirmation = await waitForCondition {
            !alerts.isEmpty
        }

        #expect(didShowConfirmation)
        #expect(!controller.isWaitingForAuthorization)
        #expect(alerts.first?.title == CurrentWallpaperAlbumStrings.addedTitle)
        #expect(alerts.first?.message == CurrentWallpaperAlbumStrings.singlePhotoRediscoveryMessage)
        #expect(photoManager.batchLookupRequests == [["ID-1/L0/001"], ["ID-1/L0/001"]])
        #expect(photoManager.albumAddRequests.count == 1)
    }

    @Test func currentWallpaperAlbumControllerRevalidatesWallpaperAfterAuthorizationWait() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager(assetsToReturn: [makeFakeAsset()])
        photoManager.managedWallpaperIdentifiers = ["ID-1/L0/001"]
        photoManager.photoLookupOverride = .waitingForAuthorization
        var alerts: [(title: String, message: String)] = []
        let controller = CurrentWallpaperAlbumController(
            historyLogger: logger,
            photoManager: photoManager) { presentation in
                alerts.append((presentation.title, presentation.message))
                return .done
            }
        logger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: ID-1/L0/001",
            screenName: "Screen 1",
            screenCount: 1,
            timestamp: Date(timeIntervalSince1970: 0))

        controller.addCurrentWallpapersToAlbum()
        let didStartWaiting = await waitForCondition {
            controller.isWaitingForAuthorization
        }

        #expect(didStartWaiting)
        photoManager.managedWallpaperIdentifiers = []
        photoManager.photoLookupOverride = nil
        photoManager.notifyPhotoAuthorizationDidChange()
        let didShowExplanation = await waitForCondition {
            !alerts.isEmpty
        }

        #expect(didShowExplanation)
        #expect(alerts.first?.title == CurrentWallpaperAlbumStrings.currentWallpaperNotSetTitle)
        #expect(photoManager.batchLookupRequests == [["ID-1/L0/001"]])
        #expect(photoManager.albumAddRequests.isEmpty)
    }

    @Test func currentWallpaperAlbumControllerTracksAlertWhileConfirmationIsPresented() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager(assetsToReturn: [makeFakeAsset()])
        photoManager.managedWallpaperIdentifiers = ["ID-1/L0/001"]
        var observedAlertState: Bool?
        var controller: CurrentWallpaperAlbumController!
        controller = CurrentWallpaperAlbumController(historyLogger: logger,
                                                     photoManager: photoManager) { _ in
            observedAlertState = controller.isPresentingAlert
            return .done
        }
        logger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: ID-1/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 1,
                                      timestamp: Date(timeIntervalSince1970: 0))

        #expect(!controller.isPresentingAlert)
        controller.addCurrentWallpapersToAlbum()
        let didShowConfirmation = await waitForCondition {
            observedAlertState != nil
        }

        #expect(didShowConfirmation)
        #expect(observedAlertState == true)
        #expect(!controller.isPresentingAlert)
    }

    @Test func appleScriptAlbumCommandIsRegisteredInTheAppBundle() {
        let appBundle = Bundle(for: AddCurrentWallpaperToPhotosWallpaperAlbumCommand.self)

        #expect(appBundle.object(forInfoDictionaryKey: "NSAppleScriptEnabled") as? Bool == true)
        #expect(appBundle.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String == "Photos Wallpaper needs permission to open the Photos Wallpaper album in Photos when you ask it to.")
        #expect(appBundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String == "PhotosWallpaper.sdef")
        #expect(appBundle.url(forResource: "PhotosWallpaper", withExtension: "sdef") != nil)
        #expect(NSClassFromString("AddCurrentWallpaperToPhotosWallpaperAlbumCommand") != nil)
    }

    @Test func appleScriptAlbumCommandReturnsAUsefulSuccessMessage() {
        let response = AddCurrentWallpaperScriptResponse(
            additionResult: .added(addedCount: 2,
                                   alreadyInAlbumCount: 0,
                                   missingIdentifierCount: 0,
                                   failedAddCount: 0))

        #expect(response.result == CurrentWallpaperAlbumStrings.twoPhotosAddedMessage)
        #expect(response.errorNumber == NSNoScriptError)
        #expect(response.errorMessage == nil)
    }

    @Test func appleScriptAlbumCommandReportsPartialFailuresAsScriptErrors() {
        let response = AddCurrentWallpaperScriptResponse(
            additionResult: .added(addedCount: 1,
                                   alreadyInAlbumCount: 0,
                                   missingIdentifierCount: 1,
                                   failedAddCount: 0))

        #expect(response.result == nil)
        #expect(response.errorNumber == NSInternalScriptError)
        let expectedMessage = CurrentWallpaperAlbumResultPresentation(
            title: CurrentWallpaperAlbumStrings.singlePhotoMissingTitle,
            message: "\(CurrentWallpaperAlbumStrings.singlePhotoAddedMessage) \(CurrentWallpaperAlbumStrings.singlePhotoMissingMessage)")
            .combinedMessage
        #expect(response.errorMessage == expectedMessage)
    }

    @Test func appleScriptAlbumCommandReturnsANoOpResultWhenNoWallpaperWasSetThisSession() {
        let response = AddCurrentWallpaperScriptResponse(additionResult: .noWallpaperSetThisSession)

        let expectedResult = CurrentWallpaperAlbumResultPresentation(
            title: CurrentWallpaperAlbumStrings.noWallpaperSetThisSessionTitle,
            message: CurrentWallpaperAlbumStrings.noWallpaperSetThisSessionMessage)
            .combinedMessage
        #expect(response.result == expectedResult)
        #expect(response.errorNumber == NSNoScriptError)
        #expect(response.errorMessage == nil)
    }

    @Test func appleScriptCoordinatorRunsTheAlbumActionWithoutShowingAnAlert() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager(assetsToReturn: [makeFakeAsset()])
        photoManager.managedWallpaperIdentifiers = ["ID-1/L0/001"]
        var alerts: [CurrentWallpaperAlbumResultPresentation] = []
        let controller = CurrentWallpaperAlbumController(
            historyLogger: logger,
            photoManager: photoManager) { presentation in
                alerts.append(presentation)
                return .done
            }
        let coordinator = AppleScriptCommandCoordinator()
        coordinator.configure(currentWallpaperAlbumController: controller)
        logger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: ID-1/L0/001",
            screenName: "Screen 1",
            screenCount: 1,
            timestamp: Date(timeIntervalSince1970: 0))
        var completedResult: CurrentWallpaperAlbumAdditionResult?

        let didStart = coordinator.addCurrentWallpapersToPhotosWallpaperAlbum {
            completedResult = $0
        }
        let didComplete = await waitForCondition {
            completedResult != nil
        }

        #expect(didStart)
        #expect(didComplete)
        #expect(completedResult == .added(addedCount: 1,
                                         alreadyInAlbumCount: 0,
                                         missingIdentifierCount: 0,
                                         failedAddCount: 0))
        #expect(alerts.isEmpty)
        #expect(photoManager.albumAddRequests.count == 1)
    }

    @Test func appleScriptCoordinatorRejectsWallpaperRememberedFromAPreviousSessionWithoutSearchingPhotos() async {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let firstSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        firstSessionLogger.recordWallpaperChange(
            photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: OLD-ID/L0/001",
            screenName: "Screen 1",
            screenCount: 1,
            timestamp: Date(timeIntervalSince1970: 0))
        let currentSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        let photoManager = FakePhotoManager()
        let controller = CurrentWallpaperAlbumController(
            historyLogger: currentSessionLogger,
            photoManager: photoManager) { _ in
                Issue.record("The AppleScript path should not show an in-app alert.")
                return .done
            }
        let coordinator = AppleScriptCommandCoordinator()
        coordinator.configure(currentWallpaperAlbumController: controller)
        var completedResult: CurrentWallpaperAlbumAdditionResult?

        let didStart = coordinator.addCurrentWallpapersToPhotosWallpaperAlbum {
            completedResult = $0
        }

        #expect(didStart)
        #expect(completedResult == .noWallpaperSetThisSession)
        #expect(photoManager.batchLookupRequests.isEmpty)
        #expect(photoManager.albumAddRequests.isEmpty)
    }

    private func currentWallpaperAlbumConfirmation(assetCount: Int,
                                                   albumAddResults: [Result<PhotosWallpaperAlbumAddResult, Error>] = [],
                                                   missingLookupIdentifiers: Set<String> = [],
                                                   expectedAlbumAddCount: Int? = nil,
                                                   expectedAlertTitle: String? = nil,
                                                   alertActions: [CurrentWallpaperAlbumAlertAction] = [.done],
                                                   albumOpenResult: Bool = true,
                                                   photosOpenResult: Bool = true) async -> (alerts: [CurrentWallpaperAlbumResultPresentation], photoManager: FakePhotoManager, albumOpener: FakePhotosAlbumOpener) {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let assets = (0..<assetCount).map { _ in makeFakeAsset() }
        let photoManager = FakePhotoManager(assetsToReturn: assets)
        photoManager.managedWallpaperIdentifiers = (1...assetCount).map { "ID-\($0)/L0/001" }
        photoManager.albumAddResults = albumAddResults
        photoManager.missingLookupIdentifiers = missingLookupIdentifiers
        let albumOpener = FakePhotosAlbumOpener(openAlbumResult: albumOpenResult,
                                                openPhotosResult: photosOpenResult)
        var alerts: [CurrentWallpaperAlbumResultPresentation] = []
        var remainingAlertActions = alertActions
        let controller = CurrentWallpaperAlbumController(historyLogger: logger,
                                                        photoManager: photoManager,
                                                        albumOpener: albumOpener) { presentation in
            alerts.append(presentation)
            return remainingAlertActions.isEmpty ? .done : remainingAlertActions.removeFirst()
        }
        let timestamp = Date(timeIntervalSince1970: 0)
        for index in 1...assetCount {
            logger.recordWallpaperChange(photoName: "IMG_000\(index).HEIC created 1 Jan 2024 at 12:00:00, id: ID-\(index)/L0/001",
                                          screenName: "Screen \(index)",
                                          screenCount: assetCount,
                                          timestamp: timestamp)
        }

        controller.addCurrentWallpapersToAlbum()
        let didShowConfirmation = await waitForCondition {
            _ = controller
            return !alerts.isEmpty
        }

        #expect(didShowConfirmation)
        if let expectedAlertTitle {
            #expect(alerts.first?.title == expectedAlertTitle)
        }
        #expect(photoManager.batchLookupRequests == [(1...assetCount).map { "ID-\($0)/L0/001" }])
        let expectedAlbumAddCount = expectedAlbumAddCount ?? assetCount
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == assets.prefix(expectedAlbumAddCount).map(ObjectIdentifier.init))
        #expect(photoManager.wallpaperAssignments.isEmpty)
        return (alerts, photoManager, albumOpener)
    }

}
