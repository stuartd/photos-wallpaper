import AppKit
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func customShortcutTracksVisibleStateColumn() throws {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let toggle = NSMenuItem(title: "Login setting", action: nil, keyEquivalent: "")
        menu.addItem(toggle)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut)
        appearance.prepare(menu)
        let view = try #require(item.view as? MenuShortcutView)
        let uncheckedWidth = view.frame.width
        #expect(view.leadingInset == 16)

        toggle.state = .on
        #expect(view.leadingInset == 30)
        #expect(view.frame.width == uncheckedWidth + 14)
        toggle.state = .off
        #expect(view.leadingInset == 16)
        #expect(view.frame.width == uncheckedWidth)

        // A checked schedule in a submenu must not indent the parent menu.
        let submenu = NSMenu()
        let selected = NSMenuItem(title: "Selected schedule", action: nil, keyEquivalent: "")
        selected.state = .on
        submenu.addItem(selected)
        toggle.submenu = submenu
        appearance.prepare(menu)
        #expect(view.leadingInset == 16)
    }

    @Test func customShortcutKeepsNativeKeyboardActivation() throws {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut,
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
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut,
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
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut,
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
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut)
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
        menu.addItem(NSMenuItem(title: "Test shortcut action", action: nil, keyEquivalent: "w"))
        var activationCount = 0
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: .defaultShortcut,
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
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut,
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
        menu.addItem(NSMenuItem(title: "Test shortcut action", action: nil, keyEquivalent: "w"))
        var transitions: [Bool] = []
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: .defaultShortcut,
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
        let appearance = MenuShortcutAppearance(title: "Test shortcut action", shortcut: .defaultShortcut,
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

    @Test func changedShortcutUpdatesHintAndConsumesOnlyTheNewBinding() throws {
        let target = FakeMenuActionTarget()
        let (menu, item) = makeShortcutMenu(target: target)
        let appearance = MenuShortcutAppearance(title: item.title, shortcut: .defaultShortcut,
                                                notificationCenter: NotificationCenter())
        appearance.prepare(menu)
        let view = try #require(item.view as? MenuShortcutView)
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.command, .control, .shift]))
        appearance.updateShortcut(custom)
        #expect(item.view === view)
        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == custom.appKitModifiers)
        #expect(view.accessibilityHelp() == custom.displayString)

        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: code == 13 ? "w" : "d", charactersIgnoringModifiers: code == 13 ? "w" : "d",
                isARepeat: false, keyCode: code))
        }
        let old = try key(13, [.control, .option])
        let changed = try key(2, custom.appKitModifiers)
        let extra = try key(2, custom.appKitModifiers.union(.option))
        let result = appearance.filterTrackingEvents([old, changed, extra])
        #expect(result.shouldActivate)
        #expect(result.remaining.count == 2)
        #expect(result.remaining.first === old)
        #expect(result.remaining.last === extra)
        #expect(!view.performKeyEquivalent(with: old))
        #expect(view.performKeyEquivalent(with: changed))
        #expect(target.activationCount == 1)

        // SwiftUI may replace the menu row after the preference changes.
        let replacement = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "w")
        replacement.target = target
        menu.removeItem(item)
        menu.addItem(replacement)
        appearance.prepare(menu)
        #expect(replacement.keyEquivalent == "d")
        #expect(replacement.keyEquivalentModifierMask == custom.appKitModifiers)
        #expect((replacement.view as? MenuShortcutView)?.accessibilityHelp() == custom.displayString)
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
