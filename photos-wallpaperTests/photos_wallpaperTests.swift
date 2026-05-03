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
            timerScheduler: scheduler
        )

        let originalTimer = scheduler.createdTimers[0]
        controller.frequency = .day

        #expect(defaults.storage["cycleFrequency"] == CycleFrequency.day.rawValue)
        #expect(originalTimer.invalidateCallCount == 1)
        #expect(scheduler.scheduledIntervals == [CycleFrequency.hour.seconds, CycleFrequency.day.seconds])
    }
}

private final class FakePhotoManager: PhotoManaging {
    func getRandomPhoto() -> PHAsset? { nil }

    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        completion(nil)
    }

    func setImageAsWallpaper(_ image: NSImage) {}
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
