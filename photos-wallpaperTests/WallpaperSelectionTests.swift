import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func cycleFrequencyAllCasesComeFromConfiguredOptions() {
        #expect(CycleFrequency.allCases == CycleFrequency.options.map(\.frequency))
    }

    @Test func cycleFrequencyPropertiesComeFromConfiguredOptions() {
        for option in CycleFrequency.options {
            #expect(option.frequency.displayName == option.displayName)
            #expect(option.frequency.seconds == option.seconds)
        }
    }

    @Test func wallpaperOrientationComesFromEffectiveDisplayDimensions() {
        #expect(WallpaperOrientation(size: CGSize(width: 2560, height: 1440)) == .landscape)
        #expect(WallpaperOrientation(size: CGSize(width: 1440, height: 2560)) == .portrait)
        #expect(WallpaperOrientation(size: CGSize(width: 1800, height: 1800)) == .square)
    }

    @Test func wallpaperPhotoSelectorMatchesEveryDisplayOrientation() {
        let assetOrientations: [WallpaperOrientation] = [.landscape, .portrait, .square, .landscape, .portrait]
        var nextRandomIndex = 0
        let selectedIndexes = WallpaperPhotoSelector.indexes(
            for: [.landscape, .portrait, .square],
            photoCount: assetOrientations.count,
            randomIndexInRange: { range in
                defer { nextRandomIndex += 1 }
                return range.lowerBound + (nextRandomIndex % (range.upperBound - range.lowerBound))
            },
            orientationAtIndex: { assetOrientations[$0] }
        )

        #expect(selectedIndexes == [0, 1, 2])
    }

    @Test func wallpaperPhotoSelectorFallsBackWhenThereAreFewerMatchingPhotosThanDisplays() {
        let assetOrientations: [WallpaperOrientation] = [.landscape, .portrait]
        var nextRandomIndex = 0
        let selectedIndexes = WallpaperPhotoSelector.indexes(
            for: [.portrait, .portrait, .landscape],
            photoCount: assetOrientations.count,
            randomIndexInRange: { range in
                defer { nextRandomIndex += 1 }
                return range.lowerBound + (nextRandomIndex % (range.upperBound - range.lowerBound))
            },
            orientationAtIndex: { assetOrientations[$0] }
        )

        #expect(selectedIndexes == [1, 0, 0])
    }

    @Test func wallpaperPhotoSelectorFallsBackWhenTheLibraryHasNoMatchingPhotoShape() {
        let assetOrientations: [WallpaperOrientation] = [.landscape, .landscape]
        var nextRandomIndex = 0
        let selectedIndexes = WallpaperPhotoSelector.indexes(
            for: [.portrait],
            photoCount: assetOrientations.count,
            randomIndexInRange: { range in
                defer { nextRandomIndex += 1 }
                return range.lowerBound + (nextRandomIndex % (range.upperBound - range.lowerBound))
            },
            orientationAtIndex: { assetOrientations[$0] }
        )

        #expect(selectedIndexes == [0])
    }

    @Test func wallpaperPhotoSelectorBoundsOrientationProbingForLargeLibraries() {
        var nextRandomIndex = 0
        var inspectedIndexes: [Int] = []

        let selectedIndexes = WallpaperPhotoSelector.indexes(
            for: [.portrait],
            photoCount: 10_000,
            randomIndexInRange: { range in
                defer { nextRandomIndex += 1 }
                return range.lowerBound + (nextRandomIndex % (range.upperBound - range.lowerBound))
            },
            orientationAtIndex: { index in
                inspectedIndexes.append(index)
                return .landscape
            }
        )

        #expect(inspectedIndexes.count == 100)
        #expect(selectedIndexes == [100])
    }

    @Test func activeUserSessionEventObservationInvalidatesEveryRegisteredNotification() {
        var invalidationCount = 0
        let observation = NotificationActiveUserSessionEventObservation(invalidations: [
            { invalidationCount += 1 },
            { invalidationCount += 1 }
        ])

        observation.invalidate()
        observation.invalidate()

        #expect(invalidationCount == 2)
    }

    @Test func singleInstanceLockRejectsSecondAcquireUntilReleased() {
        let lockURL = temporaryTestDirectory().appendingPathComponent("PhotosWallpaper.lock")
        defer { try? FileManager.default.removeItem(at: lockURL.deletingLastPathComponent()) }

        guard case .acquired(let firstLock) = SingleInstanceLock.acquire(lockURL: lockURL) else {
            Issue.record("Expected the first lock acquire to succeed.")
            return
        }

        guard case .alreadyLocked = SingleInstanceLock.acquire(lockURL: lockURL) else {
            Issue.record("Expected the second lock acquire to be rejected.")
            firstLock.release()
            return
        }

        firstLock.release()

        guard case .acquired(let reacquiredLock) = SingleInstanceLock.acquire(lockURL: lockURL) else {
            Issue.record("Expected the lock to be acquirable after release.")
            return
        }
        reacquiredLock.release()
    }

}
