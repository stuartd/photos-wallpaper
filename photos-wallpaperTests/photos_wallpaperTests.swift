//
//  photos_wallpaperTests.swift
//  photos-wallpaperTests
//
//  Created by Stuart Dunkeld on 03/05/2026.
//

import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

@MainActor
/// Controller-focused tests.
///
/// These stay at the orchestration layer: we are not testing Photos.framework or AppKit itself,
/// only that the controller asks its collaborators for the right work at the right times.
///
/// Quick testing glossary:
/// - `@testable import`: lets the test target see internal symbols from the app target.
/// - fake/mock/test double: a small stand-in object used to observe calls without touching real
///   system APIs.
struct PhotosWallpaperTests {
    @Test func cycleFrequencyAllCasesComeFromConfiguredOptions() {
        #expect(CycleFrequency.allCases == CycleFrequency.options.map(\.frequency))
    }

    @Test func cycleFrequencyPropertiesComeFromConfiguredOptions() {
        for option in CycleFrequency.options {
            #expect(option.frequency.displayName == option.displayName)
            #expect(option.frequency.seconds == option.seconds)
        }
    }


    #if DEBUG
    @Test func debugBuildIncludesOneSecondStressTestFrequency() {
        #expect(CycleFrequency.oneSecond.displayName == "Every second")
        #expect(CycleFrequency.oneSecond.seconds == 1)
    }
    #endif

    @Test func dismissingStartAtLoginPromptSuppressesFutureAutomaticPrompts() {
        let defaults = FakeDefaults()
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.notNow])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.promptToEnableStartAtLogin()
        manager.promptToEnableStartAtLogin()

        #expect(promptPresenter.askCallCount == 1)
        #expect(defaults.bool(forKey: "dismissedStartAtLoginPrompt"))
        #expect(loginItemService.registerCallCount == 0)
    }

    @Test func acceptingStartAtLoginPromptRegistersLoginItem() {
        let defaults = FakeDefaults()
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.enable])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.promptToEnableStartAtLogin()

        #expect(promptPresenter.askCallCount == 1)
        #expect(loginItemService.registerCallCount == 1)
        #expect(manager.isEnabled)
    }

    @Test func manuallyEnablingStartAtLoginClearsDismissal() {
        let defaults = FakeDefaults()
        defaults.set(true, forKey: "dismissedStartAtLoginPrompt")
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.setEnabled(true)

        #expect(defaults.bool(forKey: "dismissedStartAtLoginPrompt") == false)
        #expect(loginItemService.registerCallCount == 1)
    }

    @Test func newUserStartsWithNoScheduleAndDoesNotScheduleTimer() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        #expect(controller.frequency == nil)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(defaults.storage["cycleFrequency"] == nil)
    }

    @Test func loadsSavedFrequencyAndSchedulesTimer() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.fifteenMinutes.rawValue
        let scheduler = FakeTimerScheduler()

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        #expect(controller.frequency == .fifteenMinutes)
        let expectedIntervals: [TimeInterval] = [15 * 60]
        #expect(scheduler.scheduledIntervals == expectedIntervals)
    }

    @Test func changingFrequencyPersistsValueAndReschedulesTimer() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.hour.rawValue
        let scheduler = FakeTimerScheduler()
        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        let originalTimer = scheduler.createdTimers[0]
        controller.frequency = .day

        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.day.rawValue)
        #expect(originalTimer.invalidateCallCount == 1)
        let expectedIntervals: [TimeInterval] = [60 * 60, 60 * 60 * 24]
        #expect(scheduler.scheduledIntervals == expectedIntervals)
    }

    @Test func onLoginRunsOneWallpaperCycleWithoutSchedulingTimer() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        _ = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )
        await Task.yield()

        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func onWakeupRunsWallpaperCycleWhenWakeEventFires() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onWakeup.rawValue
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: wakeObserver,
            timerScheduler: scheduler
        )

        #expect(controller.frequency == .onWakeup)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        wakeObserver.fireWakeEvent()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func triggerNowSkipsWhilePreviousCycleIsStillRunning() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager(completesImageRequestsImmediately: false)
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()
        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        photoManager.completePendingImageRequests()
        await Task.yield()
        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 2)
    }

    @Test func triggerNowAssignsWallpaperPerScreen() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        // Use one real screen object from the host machine and duplicate it in the fake provider.
        // The controller only needs something screen-shaped; the tests are not exercising AppKit.
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }
        let screens = [baseScreen, baseScreen, baseScreen]

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: screens),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.requestedPhotoCount == 3)
        #expect(photoManager.requestedSizes == screens.map { $0.testPixelSize })
        #expect(photoManager.wallpaperAssignments.count == 3)
        #expect(photoManager.wallpaperAssignments.map(\.screen) == screens)
    }

    @Test func triggerNowReusesLastPhotoWhenThereAreFewerPhotosThanScreens() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset])
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }
        let screens = [baseScreen, baseScreen, baseScreen]

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: screens),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()

        let requestedAssetIDs = photoManager.requestedAssets.map(ObjectIdentifier.init)
        #expect(requestedAssetIDs == [
            ObjectIdentifier(firstAsset),
            ObjectIdentifier(secondAsset),
            ObjectIdentifier(secondAsset)
        ])
        #expect(photoManager.wallpaperAssignments.count == 3)
    }

    @Test func triggerNowNotifiesWhenNoPhotosAreAvailable() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let notifier = FakeWallpaperCycleNotifier()
        let photoManager = FakePhotoManager(assetsToReturn: [])
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: notifier,
            screenProvider: FakeScreenProvider(screens: [baseScreen, baseScreen, baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()

        #expect(notifier.noPhotosNotificationCount == 1)
        #expect(photoManager.requestedAssets.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func triggerNowOnlyNotifiesOnceWhileLibraryRemainsEmpty() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let notifier = FakeWallpaperCycleNotifier()
        let photoManager = FakePhotoManager(assetsToReturn: [])
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: notifier,
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()
        controller.triggerNow()
        await Task.yield()

        #expect(notifier.noPhotosNotificationCount == 1)
    }
    @Test func triggerNowWritesHistoryEntryAfterSuccessfulWallpaperUpdate() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let historyLogger = FakeWallpaperHistoryLogger()
        let photoManager = FakePhotoManager(assetNames: ["IMG_6790.HEIC"])
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: historyLogger,
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.triggerNow()
        let didRecordHistoryEntry = await historyLogger.waitForEntryCount(1)

        #expect(didRecordHistoryEntry)
        #expect(historyLogger.entries.count == 1)
        #expect(historyLogger.entries[0].photoName.contains("IMG_6790.HEIC"))
        #expect(historyLogger.entries[0].photoName.contains("created"))
        #expect(historyLogger.entries[0].photoName.contains("id:"))
        #expect(historyLogger.entries[0].screenName == "Monitor 1")
    }
}

private final class FakePhotoManager: PhotoManaging {
    private let assetsToReturn: [PHAsset]
    private let assetNames: [ObjectIdentifier: String]
    private let completesImageRequestsImmediately: Bool
    private var pendingImageCompletions: [(NSImage?) -> Void] = []
    private(set) var getRandomPhotosCallCount = 0
    private(set) var requestedPhotoCount = 0
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, screen: NSScreen)] = []
    var shouldSucceedSettingWallpaper = true

    init(assetsToReturn: [PHAsset]? = nil,
         assetNames: [String]? = nil,
         completesImageRequestsImmediately: Bool = true) {
        let assets = assetsToReturn ?? (0..<8).map { _ in makeFakeAsset() }
        self.assetsToReturn = assets
        self.completesImageRequestsImmediately = completesImageRequestsImmediately
        if let assetNames {
            self.assetNames = Dictionary(uniqueKeysWithValues: zip(assets.map(ObjectIdentifier.init), assetNames))
        } else {
            self.assetNames = [:]
        }
    }

    func getRandomPhotos(count: Int) -> PhotoSelectionResult {
        getRandomPhotosCallCount += 1
        requestedPhotoCount = count
        guard !assetsToReturn.isEmpty else { return .unavailable }
        if assetsToReturn.count >= count {
            return .photos(Array(assetsToReturn.prefix(count)))
        }

        var assets = assetsToReturn
        if let fallbackAsset = assets.last {
            assets.append(contentsOf: Array(repeating: fallbackAsset, count: count - assets.count))
        }
        return .photos(assets)
    }

    func displayName(for asset: PHAsset) -> String {
        if let assetName = assetNames[ObjectIdentifier(asset)] {
            return "\(assetName) (created Jan 1, 2024 at 12:00:00 AM, id: fake-\(ObjectIdentifier(asset).hashValue))"
        }
        return "fake-\(ObjectIdentifier(asset).hashValue)"
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

    func completePendingImageRequests() {
        let completions = pendingImageCompletions
        pendingImageCompletions.removeAll()
        for completion in completions {
            completion(NSImage(size: CGSize(width: 1, height: 1)))
        }
    }

    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) -> Bool {
        wallpaperAssignments.append((image: image, screen: screen))
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
}

private final class FakeDefaults: KeyValueStoring {
    var storage: [String: Any] = [:]

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

private final class FakeLoginItemService: LoginItemServicing {
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

private final class FakeStartAtLoginPromptPresenter: StartAtLoginPromptPresenting {
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

private final class FakeTimer: CancellableTimer {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

private final class FakeTimerScheduler: TimerScheduling {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private(set) var createdTimers: [FakeTimer] = []

    func scheduledTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> CancellableTimer {
        scheduledIntervals.append(interval)
        let timer = FakeTimer()
        createdTimers.append(timer)
        return timer
    }
}

private final class FakeWakeObservation: WakeEventObservation {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

private final class FakeWakeEventObserver: WakeEventObserving {
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

private final class FakeWallpaperCycleNotifier: WallpaperCycleNotifying {
    private(set) var noPhotosNotificationCount = 0

    func notifyNoPhotosAvailable() {
        noPhotosNotificationCount += 1
    }
}

private final class FakeWallpaperHistoryLogger: WallpaperHistoryLogging {
    private let lock = NSLock()
    private var recordedEntries: [(photoName: String, screenName: String, timestamp: Date)] = []
    private var recordedOpenCallCount = 0

    var entries: [(photoName: String, screenName: String, timestamp: Date)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEntries
    }

    var openCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedOpenCallCount
    }

    func recordWallpaperChange(photoName: String, screenName: String, timestamp: Date) {
        lock.lock()
        recordedEntries.append((photoName: photoName, screenName: screenName, timestamp: timestamp))
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

private struct FakeScreenProvider: ScreenProviding {
    let screens: [NSScreen]
}

private extension NSScreen {
    var testPixelSize: CGSize {
        CGSize(width: frame.size.width * backingScaleFactor,
               height: frame.size.height * backingScaleFactor)
    }
}

/// Tests only need unique object identity, not a real Photos asset.
///
/// `PHAsset` has no convenient public initializer for this use case, so the fake bit-casts an
/// Objective-C object reference. It is only valid for identity comparisons; do not call Photos APIs
/// on values returned from this helper.
private func makeFakeAsset() -> PHAsset {
    let object: AnyObject = NSObject()
    return unsafeBitCast(object, to: PHAsset.self)
}
