//
//  photos_wallpaperTests.swift
//  photos-wallpaperTests
//
//  Created by Stuart Dunkeld on 03/05/2026.
//

import Foundation
import AppKit
import Darwin
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
/// - fake: a small stand-in object used to observe calls without touching real system APIs.
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

    @Test func consoleLoginDateProviderChoosesMostRecentCurrentUserConsoleLoginRecord() {
        let earlierConsoleLogin = Date(timeIntervalSince1970: 100)
        let laterConsoleLogin = Date(timeIntervalSince1970: 200)
        let newestIrrelevantRecord = Date(timeIntervalSince1970: 300)
        let records = [
            UtmpxConsoleLoginDateProvider.Record(userName: "stuart",
                                                 line: "ttys000",
                                                 type: Int16(USER_PROCESS),
                                                 date: newestIrrelevantRecord),
            UtmpxConsoleLoginDateProvider.Record(userName: "becky",
                                                 line: "console",
                                                 type: Int16(USER_PROCESS),
                                                 date: newestIrrelevantRecord),
            UtmpxConsoleLoginDateProvider.Record(userName: "stuart",
                                                 line: "console",
                                                 type: Int16(DEAD_PROCESS),
                                                 date: newestIrrelevantRecord),
            UtmpxConsoleLoginDateProvider.Record(userName: "stuart",
                                                 line: "console",
                                                 type: Int16(USER_PROCESS),
                                                 date: earlierConsoleLogin),
            UtmpxConsoleLoginDateProvider.Record(userName: "stuart",
                                                 line: "console",
                                                 type: Int16(USER_PROCESS),
                                                 date: laterConsoleLogin)
        ]

        #expect(UtmpxConsoleLoginDateProvider.mostRecentConsoleLoginDate(in: records, userName: "stuart") == laterConsoleLogin)
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

    @Test func firstRunNotifierShowsMenuBarWelcomeWindowOnce() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)

        notifier.notifyIfNeeded()
        notifier.notifyIfNeeded()

        #expect(presenter.presentCallCount == 1)
        #expect(defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
    }

    @Test func firstRunNotifierSkipsMenuBarWelcomeWindowAfterPreviousRun() {
        let defaults = FakeDefaults()
        defaults.set(true, forKey: "didShowMenuBarWelcomeWindow")
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)

        notifier.notifyIfNeeded()

        #expect(presenter.presentCallCount == 0)
    }

    @Test func firstRunNotifierCanDismissWelcomeWindow() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)

        notifier.dismissWelcomeIfPresented()

        #expect(presenter.dismissCallCount == 1)
        #expect(defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
    }

    @Test func firstRunNotifierDismissSuppressesScheduledWelcomeWindow() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)

        notifier.dismissWelcomeIfPresented()
        notifier.notifyIfNeeded()

        #expect(presenter.dismissCallCount == 1)
        #expect(presenter.presentCallCount == 0)
    }

    @Test func firstRunStartupControllerDelaysWelcomeWhileModalWindowIsOpen() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)
        let modalWindowProvider = FakeModalWindowProvider(hasModalWindow: true)
        let scheduler = FakeFirstRunWelcomeScheduler()
        let controller = FirstRunStartupController(firstRunNotifier: notifier,
                                                   modalWindowProvider: modalWindowProvider,
                                                   welcomeScheduler: scheduler)

        controller.scheduleWelcomeIfNeeded()
        scheduler.fire(at: 0)

        #expect(presenter.presentCallCount == 0)
        #expect(!defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
        #expect(scheduler.scheduledDelays == [1, 0.5])

        modalWindowProvider.hasModalWindow = false
        scheduler.fire(at: 1)

        #expect(presenter.presentCallCount == 1)
        #expect(defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
    }

    @Test func firstRunStartupControllerDismissSuppressesPendingWelcomeAttempt() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)
        let scheduler = FakeFirstRunWelcomeScheduler()
        let controller = FirstRunStartupController(firstRunNotifier: notifier,
                                                   welcomeScheduler: scheduler)

        controller.scheduleWelcomeIfNeeded()
        controller.dismissWelcomeIfPresented()
        scheduler.fire(at: 0)

        #expect(presenter.dismissCallCount == 1)
        #expect(presenter.presentCallCount == 0)
        #expect(defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
    }

    @Test func appDocumentOpenerOpensSupportURL() {
        let urlOpener = FakeExternalURLOpener()
        let documentOpener = AppDocumentOpener(urlOpener: urlOpener)

        documentOpener.openSupportPage()

        #expect(urlOpener.openedURLs.map(\.absoluteString) == ["https://photos-wallpaper.app/#support"])
    }

    #if DEBUG
    @Test func debugBuildIncludesOneSecondStressTestFrequency() {
        #expect(CycleFrequency.oneSecond.displayName == "Every second")
        #expect(CycleFrequency.oneSecond.seconds == 1)
    }
    #endif

    @Test func dismissingStartAtLoginPromptSuppressesFutureAutomaticPromptsForSession() {
        let defaults = FakeDefaults()
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.notNow])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.hour.rawValue)
        manager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.day.rawValue)

        #expect(promptPresenter.askCallCount == 1)
        #expect(defaults.string(forKey: "dismissedStartAtLoginPromptSchedule") == nil)
        #expect(defaults.bool(forKey: "dismissedStartAtLoginPrompt") == false)
        #expect(loginItemService.registerCallCount == 0)
    }

    @Test func acceptingStartAtLoginPromptRegistersLoginItem() {
        let defaults = FakeDefaults()
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.enable])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.hour.rawValue)

        #expect(promptPresenter.askCallCount == 1)
        #expect(loginItemService.registerCallCount == 1)
        #expect(manager.isEnabled)
    }

    @Test func newSessionAsksOnceMoreAfterFirstStartAtLoginPromptDecline() {
        let defaults = FakeDefaults()
        let firstPromptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.notNow])
        let secondPromptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.enable])
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)

        let firstManager = LoginItemManager(defaults: defaults,
                                            loginItemService: loginItemService,
                                            promptPresenter: firstPromptPresenter)
        firstManager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.hour.rawValue)

        let secondManager = LoginItemManager(defaults: defaults,
                                             loginItemService: loginItemService,
                                             promptPresenter: secondPromptPresenter)
        secondManager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.day.rawValue)

        #expect(defaults.integer(forKey: "startAtLoginPromptDeclineCount") == 0)
        #expect(firstPromptPresenter.askCallCount == 1)
        #expect(secondPromptPresenter.askCallCount == 1)
        #expect(loginItemService.registerCallCount == 1)
        #expect(secondManager.isEnabled)
    }

    @Test func twoStartAtLoginPromptDeclinesStopFutureAutomaticPrompts() {
        let defaults = FakeDefaults()
        let firstPromptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.notNow])
        let secondPromptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.notNow])
        let thirdPromptPresenter = FakeStartAtLoginPromptPresenter(responses: [StartAtLoginPromptResponse.enable])
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)

        let firstManager = LoginItemManager(defaults: defaults,
                                            loginItemService: loginItemService,
                                            promptPresenter: firstPromptPresenter)
        firstManager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.hour.rawValue)

        let secondManager = LoginItemManager(defaults: defaults,
                                             loginItemService: loginItemService,
                                             promptPresenter: secondPromptPresenter)
        secondManager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.day.rawValue)

        let thirdManager = LoginItemManager(defaults: defaults,
                                            loginItemService: loginItemService,
                                            promptPresenter: thirdPromptPresenter)
        thirdManager.promptToEnableStartAtLogin(forSchedule: CycleFrequency.minute.rawValue)

        #expect(defaults.integer(forKey: "startAtLoginPromptDeclineCount") == 2)
        #expect(firstPromptPresenter.askCallCount == 1)
        #expect(secondPromptPresenter.askCallCount == 1)
        #expect(thirdPromptPresenter.askCallCount == 0)
        #expect(loginItemService.registerCallCount == 0)
        #expect(!thirdManager.isEnabled)
    }

    @Test func manuallyEnablingStartAtLoginClearsDismissal() {
        let defaults = FakeDefaults()
        defaults.set(2, forKey: "startAtLoginPromptDeclineCount")
        defaults.set(CycleFrequency.hour.rawValue, forKey: "dismissedStartAtLoginPromptSchedule")
        defaults.set(true, forKey: "dismissedStartAtLoginPrompt")
        let loginItemService = FakeLoginItemService(status: SMAppService.Status.notRegistered)
        let promptPresenter = FakeStartAtLoginPromptPresenter(responses: [])
        let manager = LoginItemManager(defaults: defaults,
                                       loginItemService: loginItemService,
                                       promptPresenter: promptPresenter)

        manager.setEnabled(true)

        #expect(defaults.integer(forKey: "startAtLoginPromptDeclineCount") == 0)
        #expect(defaults.string(forKey: "dismissedStartAtLoginPromptSchedule") == nil)
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
        #expect(photoManager.requestPhotoAccessCallCount == 0)
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 100),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 100))
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 200),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 100))
        )
        await Task.yield()

        #expect(relaunchedPhotoManager.getRandomPhotosCallCount == 0)
        #expect(relaunchedPhotoManager.wallpaperAssignments.isEmpty)
    }

    @Test func onLoginRunsWallpaperCycleWhenWakeEventFires() async {
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

        let controller = WallpaperCycleController(
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

        #expect(controller.frequency == .onLogin)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.wallpaperAssignments.isEmpty)

        activeUserSessionProvider.appOwnsActiveConsoleSession = true
        wakeObserver.fireWakeEvent()
        let didAssignWallpaper = await photoManager.waitForWallpaperAssignmentCount(1)

        #expect(didAssignWallpaper)
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
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )

        #expect(controller.frequency == .onLogin)

        wakeObserver.fireWakeEvent()
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
            timerScheduler: scheduler,
            screenSleepStateProvider: FakeScreenSleepStateProvider(),
            activeUserSessionProvider: FakeActiveUserSessionProvider()
        )

        #expect(controller.frequency == .onLogin)

        wakeObserver.fireWakeEvent()
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 100),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 100))
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
    }

    @Test func savedOnLoginRunsWallpaperCycleOnAppLaunchForNewLoginSession() async {
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 102),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 100))
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func savedOnLoginRunsWallpaperCycleWhenConsoleLoginMarkerSettlesAfterAppLaunch() async {
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 100),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 102))
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 1)
        #expect(photoManager.wallpaperAssignments.count == 1)
    }

    @Test func savedOnLoginDoesNotRunWallpaperCycleOnAppLaunchWhenLaunchIsNotNearLogin() async {
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
            startAtLoginStatusProvider: FakeStartAtLoginStatusProvider(isStartAtLoginEnabled: true),
            loginLaunchTimingProvider: FakeLoginLaunchTimingProvider(appLaunchDate: Date(timeIntervalSince1970: 500),
                                                                     consoleLoginDate: Date(timeIntervalSince1970: 100))
        )
        await Task.yield()

        #expect(controller.frequency == .onLogin)
        #expect(defaults.integer(forKey: "lastHandledLoginSessionIdentifier") == 42)
        #expect(scheduler.scheduledIntervals.isEmpty)
        #expect(photoManager.getRandomPhotosCallCount == 0)
        #expect(photoManager.wallpaperAssignments.isEmpty)
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
        photoManager.photoAuthorizationDidChange?()
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

    @Test func boundedLogFileCreatesMissingFileAndAppendsText() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logFile = BoundedLogFile(logURL: logURL, maxSizeBytes: 1_024, retainedLineCount: 10)

        try logFile.append("first\n")
        try logFile.append("second\n")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "first\nsecond\n")
    }

    @Test func boundedLogFileTrimsToRecentTailBeforeAppendingWhenSizeLimitWouldBeExceeded() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logFile = BoundedLogFile(logURL: logURL, maxSizeBytes: 15, retainedLineCount: 2)

        try logFile.append("one\n")
        try logFile.append("two\n")
        try logFile.append("three\n")
        try logFile.append("four\n")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "two\nthree\nfour\n")
    }

    @Test func runtimeLoggerClearsPreviousSessionLogOnStartup() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "yesterday\n".write(to: logURL, atomically: true, encoding: .utf8)

        _ = AppRuntimeLogger(logURL: logURL)

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "")
    }

    @Test func runtimeLoggerWritesHumanReadableLocalTimestamps() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = AppRuntimeLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss z"

        logger.record("hello", timestamp: timestamp)
        let didWriteLog = await waitForCondition {
            (try? String(contentsOf: logURL, encoding: .utf8)) == "[\(formatter.string(from: timestamp))] hello\n"
        }

        #expect(didWriteLog)
    }

    @Test func runtimeLoggerFormatsDiagnosticLogForAppWindow() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = AppRuntimeLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss z"

        logger.record("hello", timestamp: timestamp)
        let expectedLogText = "[\(formatter.string(from: timestamp))] hello\n"

        let didWriteLog = await waitForCondition {
            (try? String(contentsOf: logURL, encoding: .utf8)) == expectedLogText
        }

        #expect(didWriteLog)
        #expect(AppRuntimeLogger.displayText(for: expectedLogText) == "Runtime log. This file starts fresh each time Photos Wallpaper launches.\n\n\(expectedLogText)")
    }

    @Test func wallpaperHistoryLoggerClearsPreviousSessionLogOnStartup() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Photo ID OLD-ID/L0/001 was set as the wallpaper on 9 June 2026 at 13:16:18\n".write(to: logURL, atomically: true, encoding: .utf8)

        _ = WallpaperHistoryLogger(logURL: logURL)

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "")
    }

    @Test func wallpaperHistoryLoggerFormatsSessionExplanationForAppWindow() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss"

        logger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 1,
                                      timestamp: timestamp)
        let expectedHistoryText = "Photo ID FIRST-ID/L0/001 was set as the wallpaper on \(formatter.string(from: timestamp)) (IMG_0001.HEIC created 1 Jan 2024 at 12:00:00)\n"
        let historyText = try String(contentsOf: logURL, encoding: .utf8)

        #expect(historyText == expectedHistoryText)
        #expect(WallpaperHistoryLogger.displayText(for: historyText) == "Wallpaper history. This list starts fresh each time Photos Wallpaper launches.\n\n\(expectedHistoryText)")
    }

    @Test func wallpaperHistoryEntryFormatterBuildsExpectedMultipleScreenLine() {
        let photoDescription = PhotoHistoryAssetDescriptionFormatter.string(filename: "IMG_4501.JPG",
                                                                            creationDateText: "22 Dec 2015 at 11:58:17",
                                                                            localIdentifier: "A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001")

        let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoDescription,
                                                       screenName: "Screen 1",
                                                       screenCount: 2,
                                                       shownAtText: "10 June 2026 at 13:16:18")

        #expect(line == "Photo ID A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001 was set as the wallpaper for screen 1 on 10 June 2026 at 13:16:18 (IMG_4501.JPG created 22 Dec 2015 at 11:58:17)")
    }

    @Test func wallpaperHistoryEntryFormatterBuildsExpectedSingleScreenLine() {
        let photoDescription = PhotoHistoryAssetDescriptionFormatter.string(filename: "IMG_4501.JPG",
                                                                            creationDateText: "22 Dec 2015 at 11:58:17",
                                                                            localIdentifier: "A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001")

        let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoDescription,
                                                       screenName: "Screen 1",
                                                       screenCount: 1,
                                                       shownAtText: "10 June 2026 at 13:16:18")

        #expect(line == "Photo ID A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001 was set as the wallpaper on 10 June 2026 at 13:16:18 (IMG_4501.JPG created 22 Dec 2015 at 11:58:17)")
    }

    @Test func photoHistoryAssetDescriptionFormatterIncludesFilenameCreationDateAndIdentifier() {
        let singleDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                          creationDateText: "1 May 2004 at 14:42:08",
                                                                          localIdentifier: "7")
        let twoDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                       creationDateText: "11 May 2004 at 14:42:08",
                                                                       localIdentifier: "7")

        #expect(singleDigitDay == "DSCN2550.jpg created 1 May 2004 at 14:42:08, id: 7")
        #expect(twoDigitDay == "DSCN2550.jpg created 11 May 2004 at 14:42:08, id: 7")
    }

    @Test func wallpaperHistoryLoggerSnapshotsCurrentWallpaperIdentifiersByScreen() {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 0)

        logger.recordWallpaperChange(photoName: "IMG_0002.HEIC created 2 Jan 2024 at 12:00:00, id: SECOND-ID/L0/001",
                                      screenName: "Screen 2",
                                      screenCount: 2,
                                      timestamp: timestamp)
        logger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 2,
                                      timestamp: timestamp)
        logger.recordWallpaperChange(photoName: "IMG_DUPLICATE.HEIC created 3 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 3",
                                      screenCount: 3,
                                      timestamp: timestamp)

        #expect(logger.currentWallpaperIdentifiersSnapshot() == ["FIRST-ID/L0/001", "SECOND-ID/L0/001"])

        logger.recordWallpaperChange(photoName: "IMG_SINGLE.HEIC created 4 Jan 2024 at 12:00:00, id: SINGLE-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 1,
                                      timestamp: timestamp)

        #expect(logger.currentWallpaperIdentifiersSnapshot() == ["SINGLE-ID/L0/001"])
    }

    @Test func wallpaperHistoryLoggerRestoresCurrentWallpaperIdentifiersFromPreviousSession() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let timestamp = Date(timeIntervalSince1970: 0)

        let firstSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        firstSessionLogger.recordWallpaperChange(photoName: "IMG_0002.HEIC created 2 Jan 2024 at 12:00:00, id: SECOND-ID/L0/001",
                                                 screenName: "Screen 2",
                                                 screenCount: 2,
                                                 timestamp: timestamp)
        firstSessionLogger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                                 screenName: "Screen 1",
                                                 screenCount: 2,
                                                 timestamp: timestamp)

        let restoredLogger = WallpaperHistoryLogger(logURL: logURL)

        #expect(restoredLogger.currentWallpaperIdentifiersSnapshot() == ["FIRST-ID/L0/001", "SECOND-ID/L0/001"])
        #expect(try String(contentsOf: logURL, encoding: .utf8) == "")
    }

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

        #expect(result.alerts.first?.title == "Added the wallpaper photo to the Photos Wallpaper album.")
        #expect(result.alerts.first?.message == "")
    }

    @Test func currentWallpaperAlbumControllerShowsTwoWallpaperConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 2)

        #expect(result.alerts.first?.title == "Added both wallpaper photos to the Photos Wallpaper album.")
        #expect(result.alerts.first?.message == "")
    }

    @Test func currentWallpaperAlbumControllerShowsThreeOrMoreWallpaperConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 3)

        #expect(result.alerts.first?.title == "Added all wallpaper photos to the Photos Wallpaper album.")
        #expect(result.alerts.first?.message == "")
    }

    @Test func currentWallpaperAlbumControllerShowsAlreadyInAlbumConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1,
                                                             albumAddResults: [.success(.alreadyInAlbum)])

        #expect(result.alerts.first?.title == "The wallpaper photo was already in the Photos Wallpaper album.")
        #expect(result.alerts.first?.message == "")
    }

    @Test func currentWallpaperAlbumControllerShowsMixedAddedAndAlreadyInAlbumConfirmation() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 2,
                                                             albumAddResults: [.success(.added), .success(.alreadyInAlbum)])

        #expect(result.alerts.first?.title == "Added the wallpaper photo to the Photos Wallpaper album. The wallpaper photo was already in the Photos Wallpaper album.")
        #expect(result.alerts.first?.message == "")
    }

    @Test func currentWallpaperAlbumControllerExplainsMissingPhotosInPlainLanguage() async {
        let result = await currentWallpaperAlbumConfirmation(assetCount: 1,
                                                             missingLookupIdentifiers: ["ID-1/L0/001"],
                                                             expectedAlbumAddCount: 0)

        #expect(result.alerts.first?.title == "Wallpaper Photo No Longer in Photos")
        #expect(result.alerts.first?.message == "One wallpaper photo is no longer in Photos, so it could not be added.")
    }

    private func currentWallpaperAlbumConfirmation(assetCount: Int,
                                                   albumAddResults: [Result<PhotosWallpaperAlbumAddResult, Error>] = [],
                                                   missingLookupIdentifiers: Set<String> = [],
                                                   expectedAlbumAddCount: Int? = nil,
                                                   expectedAlertTitle: String? = nil) async -> (alerts: [(title: String, message: String)], photoManager: FakePhotoManager) {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let assets = (0..<assetCount).map { _ in makeFakeAsset() }
        let photoManager = FakePhotoManager(assetsToReturn: assets)
        photoManager.albumAddResults = albumAddResults
        photoManager.missingLookupIdentifiers = missingLookupIdentifiers
        var alerts: [(title: String, message: String)] = []
        let controller = CurrentWallpaperAlbumController(historyLogger: logger,
                                                        photoManager: photoManager) { title, message in
            alerts.append((title, message))
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
        return (alerts, photoManager)
    }

}

private final class FakePhotoManager: PhotoManaging {
    private let assetsToReturn: [PHAsset]
    private let assetNames: [ObjectIdentifier: String]
    private let completesImageRequestsImmediately: Bool
    var photoSelectionOverride: PhotoSelectionResult?
    var photoAccessPreflightResult: PhotoAccessPreflightResult = .ready
    private var pendingImageCompletions: [(NSImage?) -> Void] = []
    var photoAuthorizationDidChange: (() -> Void)?
    private(set) var getRandomPhotosCallCount = 0
    private(set) var requestPhotoAccessCallCount = 0
    private(set) var requestedPhotoCount = 0
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, screen: NSScreen)] = []
    private(set) var albumAddRequests: [PHAsset] = []
    private(set) var singleLookupRequests: [String] = []
    private(set) var batchLookupRequests: [[String]] = []
    var missingLookupIdentifiers = Set<String>()
    var photoLookupOverride: PhotoAssetsLookupResult?
    var albumAddResults: [Result<PhotosWallpaperAlbumAddResult, Error>] = []
    var shouldSucceedSettingWallpaper = true

    init(assetsToReturn: [PHAsset]? = nil,
         assetNames: [String]? = nil,
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
    }

    func getRandomPhotos(count: Int) -> PhotoSelectionResult {
        getRandomPhotosCallCount += 1
        requestedPhotoCount = count
        if let photoSelectionOverride { return photoSelectionOverride }
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

private final class FakeDefaults: KeyValueStoring {
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

private final class FakeFirstRunWelcomePresenter: FirstRunWelcomePresenting {
    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0

    func presentMenuBarWelcome() {
        presentCallCount += 1
    }

    func dismissMenuBarWelcome() {
        dismissCallCount += 1
    }
}

private final class FakeModalWindowProvider: AppModalWindowProviding {
    var hasModalWindow: Bool

    init(hasModalWindow: Bool) {
        self.hasModalWindow = hasModalWindow
    }
}

private final class FakeFirstRunWelcomeScheduler: FirstRunWelcomeScheduling {
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

private final class FakeTimer: CancellableTimer {
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

private final class FakeTimerScheduler: TimerScheduling {
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

private final class FakeActiveUserSessionEventObservation: ActiveUserSessionEventObservation {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

private final class FakeActiveUserSessionEventObserver: ActiveUserSessionEventObserving {
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

private final class FakeWallpaperCycleNotifier: WallpaperCycleNotifying {
    private(set) var noPhotosNotificationCount = 0
    private(set) var photoLibraryPermissionDeniedNotificationCount = 0

    func notifyNoPhotosAvailable() {
        noPhotosNotificationCount += 1
    }

    func notifyPhotoLibraryPermissionDenied() {
        photoLibraryPermissionDeniedNotificationCount += 1
    }
}

private final class FakeExternalURLOpener: ExternalURLOpening {
    private(set) var openedURLs: [URL] = []
    var openResult = true

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }
}

private final class FakeWallpaperHistoryLogger: WallpaperHistoryLogging {
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

private struct FakeScreenProvider: ScreenProviding {
    let screens: [NSScreen]
}

private final class FakeScreenSleepStateProvider: ScreenSleepStateProviding {
    var screensAreAsleep: Bool

    init(screensAreAsleep: Bool = false) {
        self.screensAreAsleep = screensAreAsleep
    }
}

private final class FakeActiveUserSessionProvider: ActiveUserSessionProviding {
    var appOwnsActiveConsoleSession: Bool

    init(appOwnsActiveConsoleSession: Bool = true) {
        self.appOwnsActiveConsoleSession = appOwnsActiveConsoleSession
    }
}

private final class FakeLoginSessionIdentifierProvider: LoginSessionIdentifying {
    var currentLoginSessionIdentifier: Int?

    init(identifier: Int?) {
        self.currentLoginSessionIdentifier = identifier
    }
}

private struct FakeStartAtLoginStatusProvider: StartAtLoginStatusProviding {
    let isStartAtLoginEnabled: Bool
}

private struct FakeLoginLaunchTimingProvider: LoginLaunchTimingProviding {
    let appLaunchDate: Date?
    let consoleLoginDate: Date?
}

private enum TestError: Error {
    case expectedFailure
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
/// Objective-C object reference and retains it for the test run. It is only valid for identity
/// comparisons; do not call Photos APIs on values returned from this helper.
private var retainedFakeAssetObjects: [AnyObject] = []

private func makeFakeAsset() -> PHAsset {
    let object: AnyObject = NSObject()
    retainedFakeAssetObjects.append(object)
    return unsafeBitCast(object, to: PHAsset.self)
}

private func temporaryTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("photos-wallpaper-tests-\(UUID().uuidString)", isDirectory: true)
}

private func waitForCondition(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
