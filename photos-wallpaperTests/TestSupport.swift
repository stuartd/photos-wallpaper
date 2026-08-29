import Foundation
import AppKit
import Photos
import ServiceManagement
@testable import photos_wallpaper

@MainActor
final class FakePhotosAlbumOpener: PhotosAlbumOpening {
    private let openAlbumResult: Bool
    private let openPhotosResult: Bool
    private(set) var openAlbumCallCount = 0
    private(set) var openPhotosCallCount = 0

    init(openAlbumResult: Bool = true, openPhotosResult: Bool = true) {
        self.openAlbumResult = openAlbumResult
        self.openPhotosResult = openPhotosResult
    }

    func openPhotosWallpaperAlbum() -> Bool {
        openAlbumCallCount += 1
        return openAlbumResult
    }

    func openPhotosApplication() -> Bool {
        openPhotosCallCount += 1
        return openPhotosResult
    }
}

final class FakePhotoManager: PhotoManaging {
    private let assetsToReturn: [PHAsset]
    private let assetNames: [ObjectIdentifier: String]
    private let assetOrientations: [ObjectIdentifier: WallpaperOrientation]
    private let completesImageRequestsImmediately: Bool
    var photoSelectionOverride: PhotoSelectionResult?
    var photoAccessPreflightResult: PhotoAccessPreflightResult = .ready
    private var pendingImageCompletions: [(NSImage?) -> Void] = []
    private var photoAuthorizationChangeHandlers: [() -> Void] = []
    private(set) var getRandomPhotosCallCount = 0
    private(set) var requestPhotoAccessCallCount = 0
    private(set) var requestedPhotoCount = 0
    private(set) var requestedDisplayOrientations: [[WallpaperOrientation]] = []
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, asset: PHAsset, screen: NSScreen)] = []
    private(set) var albumAddRequests: [PHAsset] = []
    private(set) var singleLookupRequests: [String] = []
    private(set) var batchLookupRequests: [[String]] = []
    var missingLookupIdentifiers = Set<String>()
    var photoLookupOverride: PhotoAssetsLookupResult?
    var albumAddResults: [Result<PhotosWallpaperAlbumAddResult, Error>] = []
    var shouldSucceedSettingWallpaper = true
    var managedWallpaperIdentifiers: [String] = []

    init(assetsToReturn: [PHAsset]? = nil,
         assetNames: [String]? = nil,
         assetOrientations: [WallpaperOrientation]? = nil,
         completesImageRequestsImmediately: Bool = true,
         photoSelectionOverride: PhotoSelectionResult? = nil) {
        let assets = assetsToReturn ?? (0..<8).map { _ in makeFakeAsset() }
        self.assetsToReturn = assets
        self.completesImageRequestsImmediately = completesImageRequestsImmediately
        self.photoSelectionOverride = photoSelectionOverride
        if let assetNames {
            self.assetNames = Dictionary(uniqueKeysWithValues: zip(assets.map(ObjectIdentifier.init), assetNames))
        } else {
            self.assetNames = [:]
        }
        if let assetOrientations {
            self.assetOrientations = Dictionary(uniqueKeysWithValues: zip(assets.map(ObjectIdentifier.init), assetOrientations))
        } else {
            self.assetOrientations = [:]
        }
    }

    func addPhotoAuthorizationChangeHandler(_ handler: @escaping () -> Void) {
        photoAuthorizationChangeHandlers.append(handler)
    }

    func notifyPhotoAuthorizationDidChange() {
        photoAuthorizationChangeHandlers.forEach { $0() }
    }

    func getRandomPhotos(for displayOrientations: [WallpaperOrientation]) -> PhotoSelectionResult {
        getRandomPhotosCallCount += 1
        requestedPhotoCount = displayOrientations.count
        requestedDisplayOrientations.append(displayOrientations)
        if let photoSelectionOverride { return photoSelectionOverride }
        guard !assetsToReturn.isEmpty else { return .unavailable }
        let selectedIndexes = WallpaperPhotoSelector.indexes(for: displayOrientations,
                                                             photoCount: assetsToReturn.count,
                                                             randomIndexInRange: { $0.lowerBound }) { index in
            assetOrientations[ObjectIdentifier(assetsToReturn[index]), default: .landscape]
        }
        return .photos(selectedIndexes.map { assetsToReturn[$0] })
    }

    func requestPhotoAccessIfNeeded() -> PhotoAccessPreflightResult {
        requestPhotoAccessCallCount += 1
        return photoAccessPreflightResult
    }

    func displayName(for asset: PHAsset) -> String {
        if let assetName = assetNames[ObjectIdentifier(asset)] {
            return "\(assetName) created Jan 1, 2024 at 12:00:00 AM, id: fake-\(ObjectIdentifier(asset).hashValue)"
        }
        return "fake-\(ObjectIdentifier(asset).hashValue)"
    }

    func findPhoto(localIdentifier: String) -> PhotoAssetLookupResult {
        singleLookupRequests.append(localIdentifier)
        switch findPhotos(localIdentifiers: [localIdentifier]) {
        case .photos(let assets, _):
            guard let asset = assets.first else { return .notFound }
            return .photo(asset)
        case .waitingForAuthorization:
            return .waitingForAuthorization
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        }
    }

    func findPhotos(localIdentifiers: [String]) -> PhotoAssetsLookupResult {
        batchLookupRequests.append(localIdentifiers)
        if let photoLookupOverride { return photoLookupOverride }

        var foundAssets: [PHAsset] = []
        var missingIdentifierCount = 0
        var nextAssetIndex = 0
        for identifier in localIdentifiers {
            if missingLookupIdentifiers.contains(identifier) || nextAssetIndex >= assetsToReturn.count {
                missingIdentifierCount += 1
                continue
            }

            foundAssets.append(assetsToReturn[nextAssetIndex])
            nextAssetIndex += 1
        }
        return .photos(foundAssets, missingIdentifierCount: missingIdentifierCount)
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        requestedAssets.append(asset)
        requestedSizes.append(targetSize)
        if completesImageRequestsImmediately {
            completion(NSImage(size: targetSize))
        } else {
            pendingImageCompletions.append(completion)
        }
    }

    func managedCurrentWallpaperIdentifiers() -> [String] {
        managedWallpaperIdentifiers
    }

    func completePendingImageRequests() {
        let completions = pendingImageCompletions
        pendingImageCompletions.removeAll()
        for completion in completions {
            completion(NSImage(size: CGSize(width: 1, height: 1)))
        }
    }

    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<PhotosWallpaperAlbumAddResult, Error>) -> Void) {
        albumAddRequests.append(asset)
        if albumAddResults.isEmpty {
            completion(.success(.added))
        } else {
            completion(albumAddResults.removeFirst())
        }
    }

    func setImageAsWallpaper(_ image: NSImage, from asset: PHAsset, for screen: NSScreen) -> Bool {
        wallpaperAssignments.append((image: image, asset: asset, screen: screen))
        return shouldSucceedSettingWallpaper
    }

    func waitForWallpaperAssignmentCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if wallpaperAssignments.count >= count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func waitForAlbumAddCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if albumAddRequests.count >= count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

final class FakeDefaults: KeyValueStoring {
    var storage: [String: Any] = [:]
    private(set) var setCallCounts: [String: Int] = [:]

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func integer(forKey defaultName: String) -> Int {
        storage[defaultName] as? Int ?? 0
    }

    func double(forKey defaultName: String) -> Double {
        storage[defaultName] as? Double ?? 0
    }

    func set(_ value: Any?, forKey defaultName: String) {
        setCallCounts[defaultName, default: 0] += 1
        storage[defaultName] = value
    }
}

final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

final class FakeStartAtLoginPromptPresenter: StartAtLoginPromptPresenting {
    private var responses: [StartAtLoginPromptResponse]
    private(set) var askCallCount = 0
    private(set) var shownErrors: [Error] = []

    init(responses: [StartAtLoginPromptResponse]) {
        self.responses = responses
    }

    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse {
        askCallCount += 1
        return responses.isEmpty ? .notNow : responses.removeFirst()
    }

    func showLoginItemError(_ error: Error) {
        shownErrors.append(error)
    }
}

final class FakeFirstRunWelcomePresenter: FirstRunWelcomePresenting {
    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0

    func presentMenuBarWelcome() {
        presentCallCount += 1
    }

    func dismissMenuBarWelcome() {
        dismissCallCount += 1
    }
}

final class FakeModalWindowProvider: AppModalWindowProviding {
    var hasModalWindow: Bool

    init(hasModalWindow: Bool) {
        self.hasModalWindow = hasModalWindow
    }
}

final class FakeFirstRunWelcomeScheduler: FirstRunWelcomeScheduling {
    private(set) var scheduledDelays: [TimeInterval] = []
    private var scheduledActions: [@MainActor () -> Void] = []

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        scheduledActions.append(action)
    }

    func fire(at index: Int) {
        scheduledActions[index]()
    }
}

final class FakeTimer: CancellableTimer {
    private let block: () -> Void
    private(set) var invalidateCallCount = 0

    init(block: @escaping () -> Void = {}) {
        self.block = block
    }

    func fire() {
        block()
    }

    func invalidate() {
        invalidateCallCount += 1
    }
}

final class FakeTimerScheduler: TimerScheduling {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private(set) var scheduledRepeats: [Bool] = []
    private(set) var createdTimers: [FakeTimer] = []

    func scheduledTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> CancellableTimer {
        scheduledIntervals.append(interval)
        scheduledRepeats.append(repeats)
        let timer = FakeTimer(block: block)
        createdTimers.append(timer)
        return timer
    }
}

final class FakeWakeObservation: WakeEventObservation {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

final class FakeWakeEventObserver: WakeEventObserving {
    private var handler: (() -> Void)?
    private(set) var observation = FakeWakeObservation()

    func observeWake(_ handler: @escaping () -> Void) -> WakeEventObservation {
        self.handler = handler
        return observation
    }

    func fireWakeEvent() {
        handler?()
    }
}

final class FakeActiveUserSessionEventObservation: ActiveUserSessionEventObservation {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

final class FakeActiveUserSessionEventObserver: ActiveUserSessionEventObserving {
    private var handler: (() -> Void)?
    private(set) var observation = FakeActiveUserSessionEventObservation()

    func observeSessionDidBecomeActive(_ handler: @escaping () -> Void) -> ActiveUserSessionEventObservation {
        self.handler = handler
        return observation
    }

    func fireSessionDidBecomeActive() {
        handler?()
    }
}

final class FakeWallpaperCycleNotifier: WallpaperCycleNotifying {
    private(set) var noPhotosNotificationCount = 0
    private(set) var photoLibraryPermissionDeniedNotificationCount = 0

    func notifyNoPhotosAvailable() {
        noPhotosNotificationCount += 1
    }

    func notifyPhotoLibraryPermissionDenied() {
        photoLibraryPermissionDeniedNotificationCount += 1
    }
}

final class FakeExternalURLOpener: ExternalURLOpening {
    private(set) var openedURLs: [URL] = []
    var openResult = true

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }
}

final class FakeWallpaperHistoryLogger: WallpaperHistoryLogging {
    private let lock = NSLock()
    private var recordedEntries: [(photoName: String, screenName: String, screenCount: Int, timestamp: Date)] = []
    private var recordedOpenCallCount = 0

    var entries: [(photoName: String, screenName: String, screenCount: Int, timestamp: Date)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEntries
    }

    var openCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedOpenCallCount
    }

    func recordWallpaperChange(photoName: String, screenName: String, screenCount: Int, timestamp: Date) {
        lock.lock()
        recordedEntries.append((photoName: photoName, screenName: screenName, screenCount: screenCount, timestamp: timestamp))
        lock.unlock()
    }

    func openHistoryLog() {
        lock.lock()
        recordedOpenCallCount += 1
        lock.unlock()
    }

    func waitForEntryCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if entries.count >= count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

struct FakeScreenProvider: ScreenProviding {
    let screens: [NSScreen]
}

final class FakeScreenSleepStateProvider: ScreenSleepStateProviding {
    var screensAreAsleep: Bool

    init(screensAreAsleep: Bool = false) {
        self.screensAreAsleep = screensAreAsleep
    }
}

final class FakeActiveUserSessionProvider: ActiveUserSessionProviding {
    var appOwnsActiveConsoleSession: Bool

    init(appOwnsActiveConsoleSession: Bool = true) {
        self.appOwnsActiveConsoleSession = appOwnsActiveConsoleSession
    }
}

final class FakeLoginSessionIdentifierProvider: LoginSessionIdentifying {
    var currentLoginSessionIdentifier: Int?

    init(identifier: Int?) {
        self.currentLoginSessionIdentifier = identifier
    }
}

struct FakeStartAtLoginStatusProvider: StartAtLoginStatusProviding {
    let isStartAtLoginEnabled: Bool
}

enum TestError: Error {
    case expectedFailure
}

extension NSScreen {
    var testPixelSize: CGSize {
        CGSize(width: frame.size.width * backingScaleFactor,
               height: frame.size.height * backingScaleFactor)
    }
}

/// Tests only need unique object identity, not a real Photos asset.
///
/// `PHAsset` has no convenient public initializer for this use case, so the fake bit-casts an
/// Objective-C object reference and retains it for the test run. It is only valid for identity
/// comparisons; do not call Photos APIs on values returned from this helper.
var retainedFakeAssetObjects: [AnyObject] = []

func makeFakeAsset() -> PHAsset {
    let object: AnyObject = NSObject()
    retainedFakeAssetObjects.append(object)
    return unsafeBitCast(object, to: PHAsset.self)
}

func temporaryTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("photos-wallpaper-tests-\(UUID().uuidString)", isDirectory: true)
}

func waitForCondition(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
