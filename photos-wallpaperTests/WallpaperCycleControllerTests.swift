import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
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
        #expect(photoManager.wallpaperAssignments.map { ObjectIdentifier($0.asset) }
            == photoManager.requestedAssets.map(ObjectIdentifier.init))
    }

    @Test func triggerNowReusesAPhotoWhenThereAreFewerPhotosThanScreens() async {
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

    @Test func triggerNowRetriesAfterPhotosAuthorizationChanges() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager(photoSelectionOverride: .waitingForAuthorization)
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

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(controller.isWaitingForPhotoAuthorization)

        photoManager.photoSelectionOverride = nil
        photoManager.notifyPhotoAuthorizationDidChange()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 2)
        #expect(!controller.isWaitingForPhotoAuthorization)
    }

    @Test func triggerNowNotifiesEveryTimePhotoLibraryPermissionIsDenied() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let notifier = FakeWallpaperCycleNotifier()
        let photoManager = FakePhotoManager(photoSelectionOverride: .permissionDenied)
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

        #expect(notifier.photoLibraryPermissionDeniedNotificationCount == 2)
        #expect(notifier.noPhotosNotificationCount == 0)
        #expect(photoManager.requestedAssets.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func triggerNowNotifiesEveryTimeLibraryRemainsEmpty() async {
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

        #expect(notifier.noPhotosNotificationCount == 2)
    }

    @Test func scheduledCycleOnlyNotifiesOnceWhileLibraryRemainsEmpty() async {
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
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(notifier.noPhotosNotificationCount == 1)
    }

    @Test func scheduledCycleSkipsWhileScreensAreAsleep() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func scheduledCycleSchedulesDeferredCycleFiveMinutesAfterScreensWake() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        screenSleepStateProvider.screensAreAsleep = false
        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(scheduler.scheduledIntervals == [60, 5 * 60])
        #expect(scheduler.scheduledRepeats == [true, false])

        scheduler.createdTimers.last?.fire()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
    }

    @Test func scheduledTimerDoesNotChangeWallpaperDuringWakeGracePeriod() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        screenSleepStateProvider.screensAreAsleep = false
        wakeObserver.fireWakeEvent()
        await Task.yield()

        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(scheduler.scheduledIntervals == [60, 5 * 60])

        scheduler.createdTimers.last?.fire()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
    }

    @Test func manualCycleCancelsDeferredScheduledWakeCatchUp() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        screenSleepStateProvider.screensAreAsleep = false
        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(scheduler.scheduledIntervals == [60, 5 * 60])
        let wakeCatchUpTimer = scheduler.createdTimers.last

        controller.triggerNow()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)
        await Task.yield()

        #expect(didAssignWallpaper)
        #expect(wakeCatchUpTimer?.invalidateCallCount == 1)
        #expect(photoManager.getRandomPhotosCallCount == 1)
    }

    @Test func scheduledCycleRunsAgainAfterScreensWake() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        screenSleepStateProvider.screensAreAsleep = false
        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func scheduledCycleClearsDeferredCycleAfterRegularTimerRuns() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        screenSleepStateProvider.screensAreAsleep = false
        scheduler.createdTimers.first?.fire()
        await Task.yield()
        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func scheduledCycleSkipsWhenAppUserSessionIsNotActive() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func repeatedInactiveScheduledTimerFiresDoNotKeepDeferringSameCycle() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )
        controller.frequency = .minute
        let writesAfterScheduling = defaults.setCallCounts["nextScheduledCycleDueAt"] ?? 0

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        scheduler.createdTimers.first?.fire()
        await Task.yield()
        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(defaults.setCallCounts["nextScheduledCycleDueAt"] == writesAfterScheduling + 1)
    }

    @Test func scheduledCycleResumesSelectedIntervalWhenAppUserSessionBecomesActive() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )
        controller.frequency = .minute
        let originalTimer = scheduler.createdTimers[0]

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        activeUserSessionProvider.appOwnsActiveConsoleSession = true
        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(originalTimer.invalidateCallCount == 1)
        #expect(scheduler.scheduledIntervals == [60, 60])
        #expect(scheduler.scheduledRepeats == [true, true])

        scheduler.createdTimers.last?.fire()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func overdueScheduledCycleAfterWakeResumesSelectedIntervalWhenAppUserSessionBecomesActive() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(scheduler.scheduledIntervals == [60])
        #expect(scheduler.scheduledRepeats == [true])

        activeUserSessionProvider.appOwnsActiveConsoleSession = true
        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(scheduler.scheduledIntervals == [60, 60])
        #expect(scheduler.scheduledRepeats == [true, true])

        scheduler.createdTimers.last?.fire()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
    }

    @Test func wakeCycleSkipsWhenAppUserSessionIsNotActive() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            wakeEventObserver: wakeObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )

        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func unlockCycleSkipsWhenAppUserSessionIsNotActive() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        let scheduler = FakeTimerScheduler()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )

        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func manualCycleStillRunsWhileScreensAreMarkedAsleep() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let screenSleepStateProvider = FakeScreenSleepStateProvider(screensAreAsleep: true)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: screenSleepStateProvider,
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )

        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func manualCycleStillRunsWhenAppUserSessionIsNotActive() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let activeUserSessionProvider = FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: false)
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
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: activeUserSessionProvider
        )

        controller.triggerNow()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func scheduledCycleNotifiesAgainWhenUnavailableReasonChanges() async {
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
        controller.frequency = .minute

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        photoManager.photoSelectionOverride = .permissionDenied
        scheduler.createdTimers.first?.fire()
        await Task.yield()
        scheduler.createdTimers.first?.fire()
        await Task.yield()

        #expect(notifier.noPhotosNotificationCount == 1)
        #expect(notifier.photoLibraryPermissionDeniedNotificationCount == 1)
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
        #expect(historyLogger.entries[0].screenName == "Screen 1")
        #expect(historyLogger.entries[0].screenCount == 1)
    }

}
