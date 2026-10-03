import AppKit
import Foundation
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func wallpaperShortcutLoadsSavedBindingAndInvokesAction() throws {
        let suite = "PhotosWallpaperTests.Shortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.command, .option]))
        GlobalShortcutSettingsStore(defaults: defaults).save(custom)
        let backend = FakeHotKeyBackend()
        var activations = 0
        let controller = WallpaperShortcutController(
            menuTitle: photos_wallpaperApp.changeWallpaperMenuTitle, defaults: defaults,
            backend: backend, validator: GlobalShortcutValidator(systemShortcuts: { .success([]) }, mainMenu: { nil })
        ) { activations += 1 }
        #expect(controller.shortcut == custom)
        #expect(backend.shortcuts == [custom])
        backend.action?()
        #expect(activations == 1)
    }

    @Test func wallpaperShortcutSavesOnlyAfterRegistrationAndUpdatesMenu() throws {
        let suite = "PhotosWallpaperTests.Shortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeHotKeyBackend()
        let controller = WallpaperShortcutController(
            menuTitle: photos_wallpaperApp.changeWallpaperMenuTitle, defaults: defaults,
            backend: backend, validator: GlobalShortcutValidator(systemShortcuts: { .success([]) }, mainMenu: { nil }),
            action: {})
        let menu = NSMenu()
        let item = NSMenuItem(title: photos_wallpaperApp.changeWallpaperMenuTitle, action: nil, keyEquivalent: "w")
        item.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(item)
        controller.menuAppearance.prepare(menu)
        let view = try #require(item.view as? MenuShortcutView)
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.command, .option, .shift]))

        backend.error = .alreadyRegistered
        #expect(controller.setShortcut(custom) == .alreadyRegistered)
        #expect(controller.shortcut == .defaultShortcut)
        #expect(GlobalShortcutSettingsStore(defaults: defaults).load() == .defaultShortcut)
        #expect(item.keyEquivalent == "w")

        backend.error = nil
        #expect(controller.setShortcut(custom) == nil)
        #expect(controller.shortcut == custom)
        #expect(GlobalShortcutSettingsStore(defaults: defaults).load() == custom)
        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == custom.appKitModifiers)
        #expect(view.accessibilityHelp() == custom.displayString)
        #expect(item.view === view)

        #expect(controller.setShortcut(.defaultShortcut) == nil)
        #expect(GlobalShortcutSettingsStore(defaults: defaults).load() == .defaultShortcut)
        #expect(item.keyEquivalent == "w")
    }
}
