//
//  photos_wallpaperTests.swift
//  photos-wallpaperTests
//
//  Created by Stuart Dunkeld on 03/05/2026.
//

import Foundation
import AppKit
import Photos
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
    @Test func loadsSavedFrequencyAndSchedulesTimer() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.minute.rawValue
        let scheduler = FakeTimerScheduler()

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            timerScheduler: scheduler
        )

        #expect(controller.frequency == .minute)
        #expect(scheduler.scheduledIntervals == [CycleFrequency.minute.seconds])
    }

    @Test func changingFrequencyPersistsValueAndReschedulesTimer() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            timerScheduler: scheduler
        )

        let originalTimer = scheduler.createdTimers[0]
        controller.frequency = .day

        #expect(defaults.storage["cycleFrequency"] == CycleFrequency.day.rawValue)
        #expect(originalTimer.invalidateCallCount == 1)
        #expect(scheduler.scheduledIntervals == [CycleFrequency.hour.seconds, CycleFrequency.day.seconds])
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
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.requestedPhotoCount == 3)
        #expect(photoManager.requestedSizes == screens.map(\.frame.size))
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
            timerScheduler: scheduler
        )

        controller.triggerNow()
        await Task.yield()

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
    private(set) var requestedPhotoCount = 0
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, screen: NSScreen)] = []
    var shouldSucceedSettingWallpaper = true

    init(assetsToReturn: [PHAsset]? = nil, assetNames: [String]? = nil) {
        let assets = assetsToReturn ?? (0..<8).map { _ in makeFakeAsset() }
        self.assetsToReturn = assets
        if let assetNames {
            self.assetNames = Dictionary(uniqueKeysWithValues: zip(assets.map(ObjectIdentifier.init), assetNames))
        } else {
            self.assetNames = [:]
        }
    }

    func getRandomPhotos(count: Int) -> [PHAsset] {
        requestedPhotoCount = count
        guard !assetsToReturn.isEmpty else { return [] }
        if assetsToReturn.count >= count {
            return Array(assetsToReturn.prefix(count))
        }

        var assets = assetsToReturn
        if let fallbackAsset = assets.last {
            assets.append(contentsOf: Array(repeating: fallbackAsset, count: count - assets.count))
        }
        return assets
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
        completion(NSImage(size: targetSize))
    }

    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) -> Bool {
        wallpaperAssignments.append((image: image, screen: screen))
        return shouldSucceedSettingWallpaper
    }
}

private final class FakeDefaults: KeyValueStoring {
    var storage: [String: String] = [:]

    func string(forKey defaultName: String) -> String? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value as? String
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

private final class FakeWallpaperCycleNotifier: WallpaperCycleNotifying {
    private(set) var noPhotosNotificationCount = 0

    func notifyNoPhotosAvailable() {
        noPhotosNotificationCount += 1
    }
}

private final class FakeWallpaperHistoryLogger: WallpaperHistoryLogging {
    private(set) var entries: [(photoName: String, screenName: String, timestamp: Date)] = []
    private(set) var openCallCount = 0

    func recordWallpaperChange(photoName: String, screenName: String, timestamp: Date) {
        entries.append((photoName: photoName, screenName: screenName, timestamp: timestamp))
    }

    func openHistoryLog() {
        openCallCount += 1
    }
}

private struct FakeScreenProvider: ScreenProviding {
    let screens: [NSScreen]
}

/// Tests only need unique object identity, not a real Photos asset.
///
/// `PHAsset` has no convenient public initializer, so the fake uses an object with the same memory
/// layout for identity comparisons inside tests. This is intentionally test-only and should never
/// appear in production code.
private func makeFakeAsset() -> PHAsset {
    unsafeBitCast(NSObject(), to: PHAsset.self)
}
