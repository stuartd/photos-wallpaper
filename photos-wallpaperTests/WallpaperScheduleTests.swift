import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
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

    @Test func loadsSavedFrequencyPreflightsPhotoAccessAndSchedulesTimer() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.fifteenMinutes.rawValue
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()

        let controller = WallpaperCycleController(
            photoManager: photoManager,
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
        #expect(photoManager.requestPhotoAccessCallCount == 1)
    }

    @Test func savedFrequencyMarksControllerWaitingForPhotoAuthorizationOnLaunch() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.day.rawValue
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        photoManager.photoAccessPreflightResult = .waitingForAuthorization

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        #expect(controller.frequency == .day)
        #expect(controller.isWaitingForPhotoAuthorization)
        #expect(photoManager.requestPhotoAccessCallCount == 1)
        #expect(scheduler.scheduledIntervals == [24 * 60 * 60])
    }

    @Test func savedFrequencyPreservesScheduleAndNotifiesWhenPhotoAccessWasDeniedOnLaunch() {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.day.rawValue
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        photoManager.photoAccessPreflightResult = .permissionDenied
        let notifier = FakeWallpaperCycleNotifier()

        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: notifier,
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        #expect(controller.frequency == .day)
        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.day.rawValue)
        #expect(photoManager.requestPhotoAccessCallCount == 1)
        #expect(notifier.photoLibraryPermissionDeniedNotificationCount == 1)
        #expect(scheduler.scheduledIntervals == [24 * 60 * 60])
    }

    @Test func newUserStartsWithNoScheduleAndDoesNotRequestPhotoAccess() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()

        _ = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        #expect(photoManager.requestPhotoAccessCallCount == 0)
    }

    @Test func selectingScheduledFrequencyRequestsPhotoAccessWithoutChangingWallpaper() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
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
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.frequency = .day

        #expect(photoManager.requestPhotoAccessCallCount == 1)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func selectingScheduledFrequencyMarksControllerWaitingForPhotoAuthorization() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        photoManager.photoAccessPreflightResult = .waitingForAuthorization
        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.frequency = .day

        #expect(photoManager.requestPhotoAccessCallCount == 1)
        #expect(controller.isWaitingForPhotoAuthorization)
    }

    @Test func selectingScheduledFrequencyNotifiesWhenPhotoAccessWasDenied() {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        photoManager.photoAccessPreflightResult = .permissionDenied
        let notifier = FakeWallpaperCycleNotifier()
        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: notifier,
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.frequency = .day

        #expect(photoManager.requestPhotoAccessCallCount == 1)
        #expect(notifier.photoLibraryPermissionDeniedNotificationCount == 1)
        #expect(controller.frequency == .day)
        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.day.rawValue)
        #expect(scheduler.scheduledIntervals == [24 * 60 * 60])
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func denyingPhotoAccessWhileSelectingScheduledFrequencyPreservesSchedule() async {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        photoManager.photoAccessPreflightResult = .waitingForAuthorization
        let notifier = FakeWallpaperCycleNotifier()
        let controller = WallpaperCycleController(
            photoManager: photoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: notifier,
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )

        controller.frequency = .day

        #expect(controller.frequency == .day)
        #expect(controller.isWaitingForPhotoAuthorization)
        let expectedIntervals: [TimeInterval] = [24 * 60 * 60]
        #expect(scheduler.scheduledIntervals == expectedIntervals)

        photoManager.photoAccessPreflightResult = .permissionDenied
        photoManager.notifyPhotoAuthorizationDidChange()
        await Task.yield()

        #expect(photoManager.requestPhotoAccessCallCount == 2)
        #expect(!controller.isWaitingForPhotoAuthorization)
        #expect(notifier.photoLibraryPermissionDeniedNotificationCount == 1)
        #expect(controller.frequency == .day)
        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.day.rawValue)
        #expect(scheduler.createdTimers.first?.invalidateCallCount == 0)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func savedIntervalDefersOverdueScheduledCycleOnAppLaunch() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.day.rawValue
        defaults.storage["nextScheduledCycleDueAt"] = Date(timeIntervalSince1970: 1).timeIntervalSince1970
        let scheduler = FakeTimerScheduler()
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
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler
        )
        await Task.yield()

        #expect(controller.frequency == .day)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
        #expect(defaults.double(forKey: "nextScheduledCycleDueAt") > Date().timeIntervalSince1970)

        scheduler.createdTimers.first?.fire()
        await Task.yield()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
    }

    @Test func savedIntervalDoesNotRunBeforeStoredDueTimeOnAppLaunch() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.day.rawValue
        defaults.storage["nextScheduledCycleDueAt"] = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
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

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
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

    @Test func changingFrequencyToOnLoginMarksCurrentSessionWithoutRunningWallpaperCycle() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.fiveMinutes.rawValue
        let scheduler = FakeTimerScheduler()
        let photoManager = FakePhotoManager()
        let loginSessionIdentifierProvider = FakeLoginSessionIdentifierProvider(identifier: 42)
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
            activeUserSessionProvider: FakeActiveUserSessionProvider(),
            loginSessionIdentifierProvider: loginSessionIdentifierProvider,
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true)
        )

        let originalTimer = scheduler.createdTimers[0]
        controller.frequency = .onLogin

        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.onLogin.rawValue)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(originalTimer.invalidateCallCount == 1)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        let relaunchedPhotoManager = FakePhotoManager()
        _ = WallpaperCycleController(
            photoManager: relaunchedPhotoManager,
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: [baseScreen]),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: FakeTimerScheduler(),
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(),
            loginSessionIdentifierProvider: loginSessionIdentifierProvider,
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true)
        )
        await Task.yield()

        #expect(relaunchedPhotoManager.getRandomPhotosCallCount == 0)
        #expect(relaunchedPhotoManager.wallpaperAssignments.isEmpty)
    }

    @Test func onLoginWaitsForSessionActivationAfterWakeEvent() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
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
            activeUserSessionProvider: activeUserSessionProvider,
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: false)
        )

        #expect(controller.frequency == .onLogin)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        activeUserSessionProvider.appOwnsActiveConsoleSession = true
        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func onLoginRunsWallpaperCycleWhenSessionBecomesActive() async {
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

        #expect(controller.frequency == .onLogin)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        activeUserSessionProvider.appOwnsActiveConsoleSession = true
        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func onLoginDebouncesWakeAndSessionActivationBurst() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        let scheduler = FakeTimerScheduler()
        let wakeObserver = FakeWakeEventObserver()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
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
            wakeEventObserver: wakeObserver,
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(),
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: false)
        )

        #expect(controller.frequency == .onLogin)

        wakeObserver.fireWakeEvent()
        await Task.yield()

        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        await Task.yield()
        photoManager.completePendingImageRequests()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)
        await Task.yield()

        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        await Task.yield()

        #expect(didAssignWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func manualCycleBypassesOnLoginAutomaticDebounce() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        let scheduler = FakeTimerScheduler()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
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
            wakeEventObserver: FakeWakeEventObserver(),
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(),
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: false)
        )

        #expect(controller.frequency == .onLogin)

        activeUserSessionEventObserver.fireSessionDidBecomeActive()
        let didAssignAutomaticWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)
        await Task.yield()

        controller.triggerNow()
        let didAssignManualWallpaper = await photoManager.waitForWallpaperAssignmentCount(2)

        #expect(didAssignAutomaticWallpaper)
        #expect(didAssignManualWallpaper)
        #expect(photoManager.getRandomPhotosCallCount == 2)
        #expect(photoManager.wallpaperAssignments.count == 2)
    }

    @Test func savedOnLoginDoesNotRunWallpaperCycleOnAppLaunchWhenLoginSessionWasAlreadyHandled() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        defaults.storage["lastHandledLoginSessionIdentifier"] = 42
        let scheduler = FakeTimerScheduler()
        let activeUserSessionEventObserver = FakeActiveUserSessionEventObserver()
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
            wakeEventObserver: FakeWakeEventObserver(),
            activeUserSessionEventObserver: activeUserSessionEventObserver,
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: true),
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true)
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func savedOnLoginRunsWallpaperCycleOnAppLaunchForUnhandledLoginSession() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        defaults.storage["lastHandledLoginSessionIdentifier"] = 41
        let scheduler = FakeTimerScheduler()
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
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: true),
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true)
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func savedOnLoginDoesNotRunWallpaperCycleOnAppLaunchWhenStartAtLoginIsDisabled() async {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.onLogin.rawValue
        defaults.storage["lastHandledLoginSessionIdentifier"] = 41
        let scheduler = FakeTimerScheduler()
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
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider(appOwnsActiveConsoleSession: true),
            loginSessionIdentifierProvider: FakeLoginSessionIdentifierProvider(identifier: 42),
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: false)
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

}
