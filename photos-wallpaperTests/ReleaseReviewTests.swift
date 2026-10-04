import AppKit
import Foundation
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func imageDeadlineReleasesCycleAndIgnoresLateCompletion() async throws {
        let fixture = try ReviewCycleFixture()
        let controller = fixture.controller()
        controller.triggerNow()
        await Task.yield()
        fixture.deadlines.createdTimers.last?.fire()
        await Task.yield()
        #expect(fixture.photos.cancelledImageRequestCount == 1)
        #expect(fixture.notifier.changeFailedCount == 1)
        controller.triggerNow()
        await Task.yield()
        fixture.photos.completeFirstImageRequest()
        #expect(fixture.photos.wallpaperAssignments.isEmpty)
        fixture.photos.completeFirstImageRequest()
        #expect(fixture.photos.wallpaperAssignments.count == 1)
    }

    @Test func automaticCompletionRechecksSessionSleepAndDisplay() async throws {
        for change in 0..<3 {
            let fixture = try ReviewCycleFixture()
            let controller = fixture.controller()
            controller.frequency = .minute
            fixture.timers.createdTimers.first?.fire()
            await Task.yield()
            switch change {
            case 0: fixture.session.appOwnsActiveConsoleSession = false
            case 1: fixture.sleep.screensAreAsleep = true
            default: fixture.screens.screens = []
            }
            fixture.photos.completePendingImageRequests()
            #expect(fixture.photos.wallpaperAssignments.isEmpty)
        }
    }

    @Test func disablingScheduleCancelsAutomaticRequest() async throws {
        let fixture = try ReviewCycleFixture()
        let controller = fixture.controller()
        controller.frequency = .minute
        fixture.timers.createdTimers.first?.fire()
        await Task.yield()
        controller.frequency = nil
        fixture.photos.completePendingImageRequests()
        #expect(fixture.photos.cancelledImageRequestCount == 1)
        #expect(fixture.photos.wallpaperAssignments.isEmpty)
    }

    @Test func quickLoginAuthorizationApprovalResumesOriginalCycle() async throws {
        let fixture = try ReviewCycleFixture()
        fixture.defaults.set(CycleFrequency.onLogin.rawValue, forKey: "cycleFrequency")
        fixture.photos.photoSelectionOverride = .waitingForAuthorization
        fixture.photos.photoAccessPreflightResult = .waitingForAuthorization
        let controller = fixture.controller()
        #expect(controller.isWaitingForPhotoAuthorization)
        fixture.photos.photoSelectionOverride = nil
        fixture.photos.photoAccessPreflightResult = .ready
        fixture.photos.notifyPhotoAuthorizationDidChange()
        await Task.yield()
        fixture.photos.completePendingImageRequests()
        #expect(fixture.photos.wallpaperAssignments.count == 1)
    }

    @Test func manualChangeRestartsActualTimerAndStoredDeadline() async throws {
        let fixture = try ReviewCycleFixture()
        let controller = fixture.controller()
        controller.frequency = .hour
        let originalTimer = try #require(fixture.timers.createdTimers.first)
        fixture.date = fixture.date.addingTimeInterval(59 * 60)
        controller.triggerNow()
        await Task.yield()
        fixture.photos.completePendingImageRequests()
        #expect(originalTimer.invalidateCallCount == 1)
        #expect(fixture.timers.scheduledIntervals == [3600, 3600])
        #expect(fixture.defaults.double(forKey: "nextScheduledCycleDueAt") == fixture.date.addingTimeInterval(3600).timeIntervalSince1970)
    }

    @Test func failedManualImageRequestReportsFailureAndAllowsRetry() async throws {
        let fixture = try ReviewCycleFixture()
        let controller = fixture.controller()
        controller.triggerNow()
        await Task.yield()
        fixture.photos.completeFirstImageRequest(image: nil)
        #expect(fixture.notifier.changeFailedCount == 1)
        controller.triggerNow()
        await Task.yield()
        fixture.photos.completePendingImageRequests()
        #expect(fixture.photos.wallpaperAssignments.count == 1)
    }

    @Test func appliedStateDoesNotWaitForMetadata() async throws {
        let fixture = try ReviewCycleFixture()
        fixture.photos.delaysDisplayNames = true
        let controller = fixture.controller()
        controller.triggerNow()
        await Task.yield()
        fixture.photos.completePendingImageRequests()
        #expect(fixture.history.appliedIdentifiers.count == 1)
        #expect(fixture.history.entries.isEmpty)
        fixture.photos.pendingDisplayNames.first?()
        #expect(fixture.history.entries.count == 1)
        #expect(fixture.history.entries.first?.timestamp == fixture.date)
    }

    @Test func delayedHistoryCannotOverwriteCurrentSessionWallpaper() async throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = WallpaperHistoryLogger(logURL: directory.appendingPathComponent("history.log"))
        logger.rememberAppliedWallpaper(localIdentifier: "OLD", displayIdentifier: "display-1")
        logger.rememberAppliedWallpaper(localIdentifier: "NEW", displayIdentifier: "display-1")
        logger.recordWallpaperDetails(photoName: "new.jpg, id: NEW", screenName: "Screen 1", screenCount: 1, timestamp: Date())
        logger.recordWallpaperDetails(photoName: "old.jpg, id: OLD", screenName: "Screen 1", screenCount: 1, timestamp: Date())
        #expect(logger.currentSessionWallpaperIdentifiersSnapshot() == ["NEW"])
    }

    @Test func closedLogWindowsNeverReadPresentationSnapshots() async throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reads = LockedValue(0)
        let read: @Sendable (URL) -> String? = { _ in
            reads.set(reads.get() + 1)
            return nil
        }
        let runtime = AppRuntimeLogger(logURL: directory.appendingPathComponent("runtime.log"), readLog: read)
        let history = WallpaperHistoryLogger(logURL: directory.appendingPathComponent("history.log"), readLog: read)
        for index in 0..<100 {
            runtime.record("entry \(index)")
            history.recordWallpaperDetails(photoName: "photo-\(index)", screenName: "Screen 1", screenCount: 1, timestamp: Date())
        }
        let complete = await waitForCondition {
            let runtimeText = try? String(contentsOf: directory.appendingPathComponent("runtime.log"), encoding: .utf8)
            let historyText = try? String(contentsOf: directory.appendingPathComponent("history.log"), encoding: .utf8)
            return runtimeText?.contains("entry 99") == true && historyText?.contains("photo-99") == true
        }
        #expect(complete)
        #expect(reads.get() == 0)
    }

    @Test func cacheCleanupProtectsActualURLsAndLatestDisconnectedDisplay() {
        let now = Date()
        let old = now.addingTimeInterval(-WallpaperCachePolicy.retentionInterval - 1)
        let files = [cacheFile(display: "1", date: old), cacheFile(display: "1", date: old.addingTimeInterval(1)),
                     cacheFile(display: "2", date: old), cacheFile(display: "2", date: now)]
        let removable = WallpaperCachePolicy.removableFiles(files, protectedURLs: [files[0].url], now: now)
        #expect(!removable.contains(files[0].url))
        #expect(!removable.contains(files[1].url))
        #expect(removable.contains(files[2].url))
        #expect(!removable.contains(files[3].url))
    }

    @Test func albumQueueSerializesCreationAcrossCallersAndReentrantCompletion() {
        let queue = AlbumRequestQueue()
        var finishFirst: AlbumRequestQueue.ResultHandler?
        var started: [Int] = []
        var completed: [Int] = []
        queue.enqueue(operation: { finish in
            started.append(1)
            finishFirst = finish
        }, completion: { _ in
            completed.append(1)
            queue.enqueue(operation: { finish in started.append(3); finish(.success(.added)) },
                          completion: { _ in completed.append(3) })
        })
        queue.enqueue(operation: { finish in started.append(2); finish(.success(.added)) },
                      completion: { _ in completed.append(2) })
        #expect(started == [1])
        finishFirst?(.success(.added))
        #expect(started == [1, 2, 3])
        #expect(completed == [1, 2, 3])
    }

    @Test func successfulNoOpAlbumTransactionIsFailure() {
        let result = AlbumMutationOutcome.result(transactionSucceeded: true, requestCreated: false,
                                                  containsAsset: false, error: nil)
        if case .success = result { Issue.record("A transaction without a change request must fail.") }
        let missing = AlbumMutationOutcome.result(transactionSucceeded: true, requestCreated: true,
                                                   containsAsset: false, error: nil)
        if case .success = missing { Issue.record("The photo must be present before success is reported.") }
    }

    @Test func albumQueueDeliversEachCompletionOnlyOnce() {
        let queue = AlbumRequestQueue()
        var firstCompletion: AlbumRequestQueue.ResultHandler?
        var firstResults = 0
        var secondStarts = 0
        queue.enqueue(operation: { firstCompletion = $0 }, completion: { _ in firstResults += 1 })
        queue.enqueue(operation: { _ in secondStarts += 1 }, completion: { _ in })
        firstCompletion?(.success(.added))
        firstCompletion?(.success(.added))
        #expect(firstResults == 1)
        #expect(secondStarts == 1)
    }

    @Test func structuredWallpaperStatePersistsBeforeMetadataArrives() async throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = WallpaperHistoryLogger(logURL: directory.appendingPathComponent("first.log"))
        logger.rememberAppliedWallpaper(localIdentifier: "NEW", displayIdentifier: "display-1")
        #expect(logger.currentWallpaperIdentifiersSnapshot() == ["NEW"])
        let saved = await waitForCondition {
            (try? String(contentsOf: directory.appendingPathComponent("current-wallpapers.json"), encoding: .utf8))?.contains("NEW") == true
        }
        #expect(saved)
        let restored = WallpaperHistoryLogger(logURL: directory.appendingPathComponent("second.log"))
        #expect(restored.currentWallpaperIdentifiersSnapshot() == ["NEW"])
        #expect(restored.currentSessionWallpaperIdentifiersSnapshot().isEmpty)
    }

    @Test func failedWallpaperApplicationRemovesOnlyItsNewCacheFile() throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = try #require(NSScreen.screens.first)
        let cache = directory.appendingPathComponent(".WallpaperCache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let unrelated = cache.appendingPathComponent("keep.txt")
        try "keep".write(to: unrelated, atomically: true, encoding: .utf8)
        let wallpaper = ReviewWallpaperManager()
        wallpaper.shouldFail = true
        let manager = PhotoManager(wallpaperManager: wallpaper,
            screenProvider: FakeScreenProvider(screens: [screen]), cacheDirectoryURL: cache)
        let image = NSImage(size: CGSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        for _ in 0..<3 {
            #expect(!manager.setImageAsWallpaper(image, assetLocalIdentifier: "test-asset", for: screen))
        }
        #expect(wallpaper.attempts.count == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == ["keep.txt"])
    }

    @Test func cacheCleanupProtectsWallpaperFromBeforeProcessStarted() throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = try #require(NSScreen.screens.first)
        let cache = directory.appendingPathComponent(".WallpaperCache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let oldURL = cache.appendingPathComponent("current-wallpaper-legacy.jpg")
        try Data([1]).write(to: oldURL)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: oldURL.path)
        let wallpaper = ReviewWallpaperManager()
        wallpaper.currentURL = oldURL
        // Simulate macOS still reporting the previous URL just after accepting a write.
        let manager = PhotoManager(wallpaperManager: wallpaper,
            screenProvider: FakeScreenProvider(screens: [screen]), cacheDirectoryURL: cache)
        let image = NSImage(size: CGSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        #expect(manager.setImageAsWallpaper(image, assetLocalIdentifier: "test-asset", for: screen))
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        let appliedURL = try #require(wallpaper.attempts.first)
        #expect(FileManager.default.fileExists(atPath: appliedURL.path))
    }

    @Test func unrelatedMenusKeepGlobalShortcutRegistered() {
        let center = NotificationCenter()
        let appearance = MenuShortcutAppearance(title: "Test wallpaper action", shortcut: .defaultShortcut,
            notificationCenter: center)
        var transitions: [Bool] = []
        appearance.menuTrackingChanged = { transitions.append($0) }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c"))
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        #expect(transitions.isEmpty)
    }

    @Test func physicalShortcutLabelUsesSelectedLayout() throws {
        let shortcut = GlobalShortcut.defaultShortcut
        #expect(shortcut.label(using: { _ in "z" }) == "Z")
        let yPosition = try #require(GlobalShortcut(keyCode: 16, modifiers: [.control]))
        #expect(yPosition.label(using: { _ in "z" }) == "Z")
        #expect(shortcut.label(using: { _ in nil }) == "W")
        #expect(shortcut.keyCode == 13)
    }

    @Test func photosOpeningSuspendsWithoutBlockingMainActor() async {
        var resume: CheckedContinuation<Bool, Never>?
        let opener = AppKitPhotosAlbumOpener(runAppleScript: { source in
            #expect(source.contains("with timeout of 20 seconds"))
            return await withCheckedContinuation { resume = $0 }
        }, openApplication: { true })
        let operation = Task { await opener.openPhotosWallpaperAlbum() }
        let started = await waitForCondition { resume != nil }
        #expect(started)
        resume?.resume(returning: false)
        #expect(await operation.value == false)
    }

    private func cacheFile(display: String, date: Date) -> WallpaperCacheFile {
        WallpaperCacheFile(url: URL(fileURLWithPath: "/cache/current-wallpaper-\(display)-\(UUID().uuidString).asset-YQ.jpg"), modifiedAt: date)
    }
}

@MainActor
private final class ReviewWallpaperManager: WallpaperManaging {
    var shouldFail = false
    var currentURL: URL?
    var attempts: [URL] = []

    func desktopImageURL(for screen: NSScreen) -> URL? { currentURL }
    func setWallpaper(for screen: NSScreen, to fileURL: URL, options: WallpaperOptions) throws {
        attempts.append(fileURL)
        if shouldFail { throw WallpaperError.setFailed(underlying: nil) }
    }
    func setWallpaper(for displayID: CGDirectDisplayID, to fileURL: URL, options: WallpaperOptions) throws {
        throw WallpaperError.screenNotFound
    }
    func setWallpaperOnAllScreens(to fileURL: URL, options: WallpaperOptions) throws {
        throw WallpaperError.screenNotFound
    }
}

@MainActor
private final class ReviewCycleFixture {
    let photos = FakePhotoManager(completesImageRequestsImmediately: false)
    let timers = FakeTimerScheduler()
    let deadlines = FakeTimerScheduler()
    let defaults = FakeDefaults()
    let session = FakeActiveUserSessionProvider()
    let sleep = FakeScreenSleepStateProvider()
    let notifier = FakeWallpaperCycleNotifier()
    let history = FakeWallpaperHistoryLogger()
    let screens: FakeScreenProvider
    var date = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws { screens = FakeScreenProvider(screens: [try #require(NSScreen.screens.first)]) }

    func controller() -> WallpaperCycleController {
        WallpaperCycleController(photoManager: photos, defaults: defaults, historyLogger: history,
            notifier: notifier, screenProvider: screens, wakeEventObserver: FakeWakeEventObserver(),
            activeUserSessionEventObserver: FakeActiveUserSessionEventObserver(), timerScheduler: timers,
            screenSleepStateProvider: sleep, activeUserSessionProvider: session,
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            imageDeadlineScheduler: deadlines, now: { [self] in date })
    }
}
