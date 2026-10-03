import AppKit
import Carbon
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func shortcutValidatorRejectsOnlyEnabledExactSystemBindings() {
        let shortcut = GlobalShortcut.defaultShortcut
        var validator = shortcutValidator()
        validator.systemShortcuts = {
            .success([.init(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, isEnabled: true)])
        }
        #expect(validator.error(for: shortcut) == .systemShortcut)
        validator.systemShortcuts = {
            .success([
                .init(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, isEnabled: false),
                .init(keyCode: shortcut.keyCode, modifiers: UInt32(cmdKey), isEnabled: true),
                .init(keyCode: 2, modifiers: shortcut.carbonModifiers, isEnabled: true)
            ])
        }
        #expect(validator.error(for: shortcut) == nil)
    }

    @Test func shortcutValidatorIgnoresOwnCommandAndChecksDisabledNestedCommands() throws {
        let menu = NSMenu()
        let own = NSMenuItem(title: photos_wallpaperApp.changeWallpaperMenuTitle, action: nil, keyEquivalent: "w")
        own.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(own)
        var validator = shortcutValidator(menu: menu)
        validator.isShortcutItem = { $0 === own }
        #expect(validator.error(for: .defaultShortcut) == nil)

        let submenu = NSMenu()
        let parent = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.isEnabled = false
        submenu.addItem(quit)
        let commandQ = try #require(GlobalShortcut(keyCode: 12, modifiers: [.command]))
        #expect(validator.error(for: commandQ) == .menuItem(quit.title))
        // Menu bindings are read again after changes.
        quit.keyEquivalent = "d"
        #expect(validator.error(for: commandQ) == nil)
    }

    @Test func shortcutValidatorUsesLayoutAndImplicitShift() throws {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Custom command", action: nil, keyEquivalent: "D")
        item.keyEquivalentModifierMask = [.command]
        menu.addItem(item)
        var validator = shortcutValidator(menu: menu)
        validator.characters = { _, shifted in shifted ? "D" : "d" }
        let shortcut = try #require(GlobalShortcut(keyCode: 8, modifiers: [.command, .shift]))
        #expect(validator.error(for: shortcut) == .menuItem(item.title))

        item.keyEquivalent = "?"
        validator.characters = { _, shifted in shifted ? "?" : "/" }
        let punctuation = try #require(GlobalShortcut(keyCode: 44, modifiers: [.command, .shift]))
        #expect(validator.error(for: punctuation) == .menuItem(item.title))
        item.keyEquivalentModifierMask.insert(.shift)
        #expect(validator.error(for: punctuation) == .menuItem(item.title))
    }

    @Test func shortcutValidatorReportsSystemAndKeyboardLayoutFailures() {
        var validator = shortcutValidator(menu: NSMenu())
        validator.systemShortcuts = { .failure(.systemCheckFailed(-108)) }
        #expect(validator.error(for: .defaultShortcut) == .systemCheckFailed(-108))
        validator.systemShortcuts = { .success([]) }
        validator.characters = { _, _ in nil }
        #expect(validator.error(for: .defaultShortcut) == .keyboardLayoutUnavailable)
    }

    private func shortcutValidator(menu: NSMenu? = nil) -> GlobalShortcutValidator {
        GlobalShortcutValidator(systemShortcuts: { .success([]) }, mainMenu: { menu },
                                characters: { shortcut, shifted in
            shifted ? shortcut.keyLabel : shortcut.keyLabel.lowercased()
        })
    }
}
