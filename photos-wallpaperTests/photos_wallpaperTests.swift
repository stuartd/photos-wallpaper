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
struct PhotosWallpaperTests {
    @Test func loadsSavedFrequencyAndSchedulesTimer() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.minute.rawValue
        let scheduler = FakeTimerScheduler()

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
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
        guard let baseScreen = NSScreen.screens.first else {
            Issue.record("Expected at least one screen for wallpaper tests.")
            return
        }
        let screens = [baseScreen, baseScreen, baseScreen]

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
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
}

private final class FakePhotoManager: PhotoManaging {
    private let assetsToReturn: [PHAsset]
    private(set) var requestedPhotoCount = 0
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, screen: NSScreen)] = []

    init(assetsToReturn: [PHAsset]? = nil) {
        self.assetsToReturn = assetsToReturn ?? (0..<8).map { _ in makeFakeAsset() }
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

    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        requestedAssets.append(asset)
        requestedSizes.append(targetSize)
        completion(NSImage(size: targetSize))
    }

    func setImageAsWallpaper(_ image: NSImage, for screen: NSScreen) {
        wallpaperAssignments.append((image: image, screen: screen))
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

private struct FakeScreenProvider: ScreenProviding {
    let screens: [NSScreen]
}

private func makeFakeAsset() -> PHAsset {
    unsafeBitCast(NSObject(), to: PHAsset.self)
}
