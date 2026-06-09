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

    @Test func migratesSavedFrequencyFromLegacyPreferencesWhenCurrentDefaultsAreEmpty() throws {
        let defaults = FakeDefaults()
        let scheduler = FakeTimerScheduler()
        let legacyDefaultsURL = temporaryTestDirectory().appendingPathComponent("com.rosehillsolutions.photoswallpaper.plist")
        defer { try? FileManager.default.removeItem(at: legacyDefaultsURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: legacyDefaultsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        NSDictionary(dictionary: ["cycleFrequency": CycleFrequency.fiveMinutes.rawValue])
            .write(to: legacyDefaultsURL, atomically: true)

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler,
            legacyDefaultsURL: legacyDefaultsURL
        )

        #expect(controller.frequency == .fiveMinutes)
        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.fiveMinutes.rawValue)
        let expectedIntervals: [TimeInterval] = [5 * 60]
        #expect(scheduler.scheduledIntervals == expectedIntervals)
    }

    @Test func currentSavedFrequencyWinsOverLegacyPreferences() throws {
        let defaults = FakeDefaults()
        defaults.storage["cycleFrequency"] = CycleFrequency.day.rawValue
        let scheduler = FakeTimerScheduler()
        let legacyDefaultsURL = temporaryTestDirectory().appendingPathComponent("com.rosehillsolutions.photoswallpaper.plist")
        defer { try? FileManager.default.removeItem(at: legacyDefaultsURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: legacyDefaultsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        NSDictionary(dictionary: ["cycleFrequency": CycleFrequency.fiveMinutes.rawValue])
            .write(to: legacyDefaultsURL, atomically: true)

        let controller = WallpaperCycleController(
            photoManager: FakePhotoManager(),
            defaults: defaults,
            historyLogger: FakeWallpaperHistoryLogger(),
            notifier: FakeWallpaperCycleNotifier(),
            screenProvider: FakeScreenProvider(screens: []),
            wakeEventObserver: FakeWakeEventObserver(),
            timerScheduler: scheduler,
            legacyDefaultsURL: legacyDefaultsURL
        )

        #expect(controller.frequency == .day)
        #expect(defaults.string(forKey: "cycleFrequency") == CycleFrequency.day.rawValue)
        let expectedIntervals: [TimeInterval] = [60 * 60 * 24]
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

    @Test func photoHistoryIdentifierAcceptsRawIdentifier() {
        #expect(PhotoHistoryIdentifier.extract(from: " 3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001 ") == "3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001")
    }

    @Test func wallpaperHistoryEntryFormatterBuildsExpectedLine() {
        let photoDescription = PhotoHistoryAssetDescriptionFormatter.string(filename: "IMG_6790.HEIC",
                                                                            creationDateText: "Jan 1, 2026 at 12:00:00 AM",
                                                                            localIdentifier: "3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001")

        let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoDescription,
                                                       screenName: "Screen 1",
                                                       shownAtText: "January 1, 2026 at 12:00:00 AM")

        #expect(line == "IMG_6790.HEIC created Jan 1, 2026 at 12:00:00 AM,  id: 3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001 was shown on Screen 1 on January 1, 2026 at 12:00:00 AM")
        #expect(PhotoHistoryIdentifier.exampleHistoryLine == line)
    }

    @Test func photoHistoryAssetDescriptionFormatterPadsSingleDigitCreationDays() {
        let singleDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                          creationDateText: "1 May 2004 at 14:42:08",
                                                                          localIdentifier: "7")
        let twoDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                       creationDateText: "11 May 2004 at 14:42:08",
                                                                       localIdentifier: "7")

        #expect(singleDigitDay == "DSCN2550.jpg created 1 May 2004 at 14:42:08,  id: 7")
        #expect(twoDigitDay    == "DSCN2550.jpg created 11 May 2004 at 14:42:08, id: 7")
    }

    @Test func photoHistoryIdentifierAcceptsWholeHistoryLine() {
        let line = "IMG_6790.HEIC created Jan 1, 2024 at 12:00:00 AM, id: 3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001 was shown on Screen 1"

        #expect(PhotoHistoryIdentifier.extract(from: line) == "3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001")
    }

    @Test func photoHistoryIdentifierAcceptsOlderParenthesizedHistoryLine() {
        let line = "IMG_6790.HEIC (created Jan 1, 2024 at 12:00:00 AM, id: 3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001) was shown on Screen 1"

        #expect(PhotoHistoryIdentifier.extract(from: line) == "3C21E42E-01A1-4985-862B-F44C5B57A786/L0/001")
    }

    @Test func photoHistoryIdentifierExtractsMultipleHistoryLines() {
        let text = """
        IMG_0001.HEIC created Jan 1, 2024 at 12:00:00 AM, id: FIRST-ID/L0/001 was shown on Screen 1
        IMG_0002.HEIC created Jan 2, 2024 at 12:00:00 AM, id: SECOND-ID/L0/001 was shown on Screen 1
        IMG_0003.HEIC created Jan 3, 2024 at 12:00:00 AM, id: THIRD-ID/L0/001 was shown on Screen 1
        """

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text)

        #expect(result.identifiers == ["FIRST-ID/L0/001", "SECOND-ID/L0/001", "THIRD-ID/L0/001"])
        #expect(!result.isPasteTooLarge)
        #expect(!result.didReachIdentifierLimit)
    }

    @Test func photoHistoryIdentifierDeduplicatesIdentifiers() {
        let text = """
        IMG_0001.HEIC (id: SAME-ID/L0/001) was shown on Screen 1
        IMG_0001.HEIC (id: SAME-ID/L0/001) was shown on Screen 1
        IMG_0002.HEIC (id: OTHER-ID/L0/001) was shown on Screen 1
        """

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text)

        #expect(result.identifiers == ["SAME-ID/L0/001", "OTHER-ID/L0/001"])
    }

    @Test func photoHistoryIdentifierAcceptsMultipleRawIdentifierLines() {
        let text = """
        FIRST-ID/L0/001
        SECOND-ID/L0/001
        """

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text)

        #expect(result.identifiers == ["FIRST-ID/L0/001", "SECOND-ID/L0/001"])
    }

    @Test func photoHistoryIdentifierAcceptsMixedHistoryLinesAndRawIdentifierLines() {
        let text = """
        IMG_0001.HEIC created Jan 1, 2024 at 12:00:00 AM, id: FIRST-ID/L0/001 was shown on Screen 1
        SECOND-ID/L0/001
        IMG_0003.HEIC created Jan 3, 2024 at 12:00:00 AM, id: THIRD-ID/L0/001 was shown on Screen 1
        """

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text)

        #expect(result.identifiers == ["FIRST-ID/L0/001", "SECOND-ID/L0/001", "THIRD-ID/L0/001"])
    }

    @Test func photoHistoryIdentifierRejectsLargePastes() {
        let result = PhotoHistoryIdentifier.extractIdentifiers(from: String(repeating: "a", count: 11),
                                                               maxCharacterCount: 10)

        #expect(result.identifiers.isEmpty)
        #expect(result.isPasteTooLarge)
        #expect(!result.didReachIdentifierLimit)
    }

    @Test func photoHistoryIdentifierStopsAtIdentifierLimit() {
        let text = (1...5)
            .map { "IMG_\($0).HEIC (id: ID-\($0)/L0/001) was shown on Screen 1" }
            .joined(separator: "\n")

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text, maxIdentifierCount: 3)

        #expect(result.identifiers == ["ID-1/L0/001", "ID-2/L0/001", "ID-3/L0/001"])
        #expect(result.didReachIdentifierLimit)
    }

    @Test func photoHistoryIdentifierDoesNotTreatLogTextWithoutIdentifierAsRawIdentifier() {
        let text = "IMG_6790.HEIC was shown on Screen 1 on January 1, 2026 at 12:00:00 AM"

        let result = PhotoHistoryIdentifier.extractIdentifiers(from: text)

        #expect(result.identifiers.isEmpty)
    }

    @Test func photoHistoryPhotoFinderUsesOneBatchLookupAndPreservesSummaryData() {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset])
        photoManager.missingLookupIdentifiers = ["MISSING-ID/L0/001"]
        let extractionResult = PhotoHistoryIdentifier.ExtractionResult(
            identifiers: ["FIRST-ID/L0/001", "MISSING-ID/L0/001", "SECOND-ID/L0/001"],
            isPasteTooLarge: false,
            didReachIdentifierLimit: true
        )

        let result = PhotoHistoryPhotoFinder(photoManager: photoManager).findPhotos(for: extractionResult)

        guard case .photos(let assets, let missingIdentifierCount, let didReachIdentifierLimit) = result else {
            Issue.record("Expected photo lookup to return found assets.")
            return
        }
        #expect(photoManager.batchLookupRequests == [["FIRST-ID/L0/001", "MISSING-ID/L0/001", "SECOND-ID/L0/001"]])
        #expect(photoManager.singleLookupRequests.isEmpty)
        #expect(assets.map(ObjectIdentifier.init) == [ObjectIdentifier(firstAsset), ObjectIdentifier(secondAsset)])
        #expect(missingIdentifierCount == 1)
        #expect(didReachIdentifierLimit)
    }

    @Test func photoHistoryPhotoFinderPropagatesAuthorizationFailures() {
        let extractionResult = PhotoHistoryIdentifier.ExtractionResult(
            identifiers: ["FIRST-ID/L0/001"],
            isPasteTooLarge: false,
            didReachIdentifierLimit: false
        )
        let photoManager = FakePhotoManager()

        photoManager.photoLookupOverride = .waitingForAuthorization
        if case .waitingForAuthorization = PhotoHistoryPhotoFinder(photoManager: photoManager).findPhotos(for: extractionResult) {
            #expect(true)
        } else {
            Issue.record("Expected waiting-for-authorization lookup result.")
        }

        photoManager.photoLookupOverride = .permissionDenied
        if case .permissionDenied = PhotoHistoryPhotoFinder(photoManager: photoManager).findPhotos(for: extractionResult) {
            #expect(true)
        } else {
            Issue.record("Expected permission-denied lookup result.")
        }

        photoManager.photoLookupOverride = .unavailable
        if case .unavailable = PhotoHistoryPhotoFinder(photoManager: photoManager).findPhotos(for: extractionResult) {
            #expect(true)
        } else {
            Issue.record("Expected unavailable lookup result.")
        }
    }

    @Test func photoHistoryLookupViewModelAddsEveryFoundAssetToAlbum() async {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset],
                                            completesImageRequestsImmediately: false)
        let viewModel = PhotoHistoryLookupViewModel(assets: [firstAsset, secondAsset],
                                                    missingIdentifierCount: 1,
                                                    didReachIdentifierLimit: true,
                                                    photoManager: photoManager)

        viewModel.addToAlbum()
        let didAddAssets = await photoManager.waitForAlbumAddCount(2)
        let didFinishUpdatingViewModel = await waitForCondition {
            viewModel.didAddToAlbum
        }

        #expect(didAddAssets)
        #expect(didFinishUpdatingViewModel)
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [ObjectIdentifier(firstAsset), ObjectIdentifier(secondAsset)])
        #expect(viewModel.didAddToAlbum)
        #expect(viewModel.statusMessage == "Added 2 photos to the Photos Wallpaper album.")
        #expect(viewModel.summary.contains("2 photos ready to add."))
        #expect(viewModel.summary.contains("1 history entry could not be found."))
        #expect(viewModel.summary.contains("Only the first 25 matching entries were processed."))
    }

    @Test func photoHistoryLookupViewModelReportsPartialAlbumAddFailures() async {
        let firstAsset = makeFakeAsset()
        let secondAsset = makeFakeAsset()
        let thirdAsset = makeFakeAsset()
        let photoManager = FakePhotoManager(assetsToReturn: [firstAsset, secondAsset, thirdAsset])
        photoManager.albumAddResults = [
            .success(()),
            .failure(TestError.expectedFailure),
            .success(())
        ]
        let viewModel = PhotoHistoryLookupViewModel(assets: [firstAsset, secondAsset, thirdAsset],
                                                    missingIdentifierCount: 0,
                                                    didReachIdentifierLimit: false,
                                                    photoManager: photoManager)

        viewModel.addToAlbum()
        let didAddAssets = await photoManager.waitForAlbumAddCount(3)
        let didFinishUpdatingViewModel = await waitForCondition {
            viewModel.statusMessage == "Added 2 photos. 1 photo could not be added."
        }

        #expect(didAddAssets)
        #expect(didFinishUpdatingViewModel)
        #expect(!viewModel.didAddToAlbum)
        #expect(!viewModel.isAddingToAlbum)
        #expect(photoManager.albumAddRequests.map(ObjectIdentifier.init) == [
            ObjectIdentifier(firstAsset),
            ObjectIdentifier(secondAsset),
            ObjectIdentifier(thirdAsset)
        ])
    }
}

private final class FakePhotoManager: PhotoManaging {
    private let assetsToReturn: [PHAsset]
    private let assetNames: [ObjectIdentifier: String]
    private let completesImageRequestsImmediately: Bool
    var photoSelectionOverride: PhotoSelectionResult?
    private var pendingImageCompletions: [(NSImage?) -> Void] = []
    private(set) var getRandomPhotosCallCount = 0
    private(set) var requestedPhotoCount = 0
    private(set) var requestedAssets: [PHAsset] = []
    private(set) var requestedSizes: [CGSize] = []
    private(set) var wallpaperAssignments: [(image: NSImage, screen: NSScreen)] = []
    private(set) var albumAddRequests: [PHAsset] = []
    private(set) var singleLookupRequests: [String] = []
    private(set) var batchLookupRequests: [[String]] = []
    var missingLookupIdentifiers = Set<String>()
    var photoLookupOverride: PhotoAssetsLookupResult?
    var albumAddResults: [Result<Void, Error>] = []
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

    func addToPhotosWallpaperAlbum(asset: PHAsset, completion: @escaping (Result<Void, Error>) -> Void) {
        albumAddRequests.append(asset)
        if albumAddResults.isEmpty {
            completion(.success(()))
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

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func integer(forKey defaultName: String) -> Int {
        storage[defaultName] as? Int ?? 0
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
    private(set) var createdTimers: [FakeTimer] = []

    func scheduledTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> CancellableTimer {
        scheduledIntervals.append(interval)
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
/// Objective-C object reference. It is only valid for identity comparisons; do not call Photos APIs
/// on values returned from this helper.
private func makeFakeAsset() -> PHAsset {
    let object: AnyObject = NSObject()
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
