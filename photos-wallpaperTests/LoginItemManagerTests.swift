import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
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

}
