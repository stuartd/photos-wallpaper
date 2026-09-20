import AppKit
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func customShortcutKeepsNativeKeyboardActivation() throws {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: "⌃⌥W",
                                                notificationCenter: NotificationCenter())
        let originalAction = item.action
        appearance.prepare(menu)

        #expect(item.view is MenuShortcutView)
        #expect(item.target === target)
        #expect(item.action == originalAction)
        #expect(item.keyEquivalent == "w")
        #expect(item.keyEquivalentModifierMask == [.control, .option])
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control, .option],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        #expect(menu.performKeyEquivalent(with: event))
        #expect(target.activationCount == 1)
        item.isEnabled = false
        _ = menu.performKeyEquivalent(with: event)
        #expect(target.activationCount == 1)
    }

    @Test func customShortcutForwardsClickAndAccessibilityToOriginalAction() throws {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: "⌃⌥W",
                                                notificationCenter: NotificationCenter())
        appearance.prepare(menu)
        let view = try #require(item.view as? MenuShortcutView)

        #expect(view.activate())
        #expect(target.activationCount == 1)
        #expect(view.accessibilityPerformPress())
        #expect(target.activationCount == 2)

        item.isEnabled = false
        #expect(!view.activate())
        #expect(!view.accessibilityPerformPress())
        #expect(!view.isAccessibilityEnabled())
        #expect(target.activationCount == 2)
    }

    @Test func customShortcutIsInstalledOnMenuOpeningWithoutChangingOtherRows() {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let otherItem = NSMenuItem(title: "Other command", action: nil, keyEquivalent: "")
        menu.addItem(otherItem)
        let center = NotificationCenter()
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: "⌃⌥W",
                                                notificationCenter: center)

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        let firstView = item.view
        #expect(firstView is MenuShortcutView)
        #expect(otherItem.view == nil)
        appearance.prepare(menu)
        #expect(item.view === firstView)
        #expect(menu.items.count == 2)
    }

    @Test func customShortcutFollowsNativeMenuCreationAndReplacement() {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: "⌃⌥W")
        menu.removeItem(item)
        menu.addItem(item)
        #expect(item.view is MenuShortcutView)

        // SwiftUI may clear the view when it refreshes a command's state.
        item.view = nil
        appearance.prepare(menu)
        #expect(item.view is MenuShortcutView)
        #expect(item.keyEquivalent == "w")
    }

    @Test func globalShortcutClosesTrackingMenuBeforeStartingAction() {
        let center = NotificationCenter()
        let menu = FakeTrackingMenu()
        var activationCount = 0
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: "⌃⌥W",
                                                notificationCenter: center) {
            #expect(menu.didCancelTracking)
            activationCount += 1
        }
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        appearance.activateShortcut()
        #expect(activationCount == 1)
    }

    @Test func globalShortcutRespectsDisabledOpenMenuAndWorksAfterItCloses() {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let center = NotificationCenter()
        var activationCount = 0
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: "⌃⌥W",
                                                notificationCenter: center) {
            activationCount += 1
        }
        item.isEnabled = false
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        appearance.activateShortcut()
        #expect(activationCount == 0)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        appearance.activateShortcut()
        #expect(activationCount == 1)
    }

    @Test func menuTrackingSwitchesShortcutDeliveryAndRestoresItAfterClosing() {
        let center = NotificationCenter()
        let menu = FakeTrackingMenu()
        var transitions: [Bool] = []
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: "⌃⌥W",
                                                notificationCenter: center) {
            #expect(transitions == [true, false])
        }
        appearance.menuTrackingChanged = { transitions.append($0) }
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        #expect(transitions == [true])
        appearance.activateShortcut()
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        #expect(transitions == [true, false])

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        #expect(transitions == [true, false, true, false])
    }

    @Test func trackingEventsConsumeOnlyShortcutAndIgnoreKeyRepeat() throws {
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: "⌃⌥W",
                                                notificationCenter: NotificationCenter())
        func key(_ modifiers: NSEvent.ModifierFlags, repeated: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "w", charactersIgnoringModifiers: "w", isARepeat: repeated, keyCode: 13))
        }
        let plain = try key([])
        let shortcut = try key([.control, .option])
        let extraModifier = try key([.control, .option, .shift])
        let repeatKey = try key([.control, .option], repeated: true)
        let result = appearance.filterTrackingEvents([plain, shortcut, extraModifier, repeatKey])
        #expect(result.shouldActivate)
        #expect(result.remaining.count == 2)
        #expect(result.remaining.first === plain)
        #expect(result.remaining.last === extraModifier)
        let repeats = appearance.filterTrackingEvents([repeatKey])
        #expect(!repeats.shouldActivate)
        #expect(repeats.remaining.isEmpty)
    }

    private func makeShortcutMenu(target: FakeMenuActionTarget) -> (NSMenu, NSMenuItem) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Test shortcut action",
                              action: #selector(FakeMenuActionTarget.activate(_:)),
                              keyEquivalent: "w")
        item.keyEquivalentModifierMask = [.control, .option]
        item.target = target
        menu.addItem(item)
        return (menu, item)
    }
}

@MainActor
private final class FakeMenuActionTarget: NSObject {
    private(set) var activationCount = 0

    @objc func activate(_ sender: NSMenuItem) {
        activationCount += 1
    }
}

@MainActor
private final class FakeTrackingMenu: NSMenu {
    private(set) var didCancelTracking = false

    override func cancelTracking() {
        didCancelTracking = true
    }
}
