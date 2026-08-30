import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func firstRunNotifierShowsMenuBarWelcomeWindowOnce() {
        let defaults = FakeDefaults()
        let presenter = FakeFirstRunWelcomePresenter()
        let notifier = FirstRunNotifier(defaults: defaults, presenter: presenter)

        notifier.notifyIfNeeded()
        notifier.notifyIfNeeded()

        #expect(presenter.presentCallCount == 1)
        #expect(defaults.bool(forKey: "didShowMenuBarWelcomeWindow"))
    }

    @Test func firstRunWelcomeReferencesFindCurrentWallpaperMenuCommand() {
        let menuTitle = photos_wallpaperApp.findCurrentWallpaperMenuTitle
            .trimmingCharacters(in: .punctuationCharacters)

        #expect(AppKitFirstRunWelcomePresenter.welcomeMessage.contains(menuTitle))
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

}
