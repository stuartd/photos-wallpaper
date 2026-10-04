import Foundation
import SwiftUI
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func shortcutLabelsPreserveKeysWhoseUppercaseExpands() throws {
        let shortcut = try #require(GlobalShortcut(keyCode: 27, modifiers: [.control, .option]))
        for character in ["ß", "ﬃ"] {
            #expect(shortcut.label(using: { _ in character }) == character)
            #expect(shortcut.keyEquivalentCharacters(using: { _ in character }) == character)
            #expect(shortcut.keyEquivalent(using: { _ in character }).character == Character(character))
        }
        #expect(shortcut.keyCode == 27)
        for unavailable: String? in [nil, ""] {
            #expect(shortcut.keyEquivalent(using: { _ in unavailable }).character == "-")
        }
    }

    @Test func shortcutNativeEquivalentsFollowLayoutWithoutDisplayCapitalization() {
        let shortcut = GlobalShortcut.defaultShortcut
        #expect(shortcut.label(using: { _ in "z" }) == "Z")
        #expect(shortcut.keyEquivalentCharacters(using: { _ in "z" }) == "z")
        #expect(shortcut.keyEquivalent(using: { _ in "z" }).character == "z")
        #expect(shortcut.label(using: { _ in "é" }) == "É")
        #expect(shortcut.keyEquivalentCharacters(using: { _ in "é" }) == "é")
        #expect(shortcut.keyEquivalent(using: { _ in "é" }).character == "é")
        for unavailable: String? in [nil, ""] {
            #expect(shortcut.label(using: { _ in unavailable }) == "W")
            #expect(shortcut.keyEquivalentCharacters(using: { _ in unavailable }) == "w")
        }
    }

    @Test func shortcutDefaultAndAllowedKeys() {
        #expect(GlobalShortcut.defaultShortcut.keyCode == 13)
        #expect(GlobalShortcut.defaultShortcut.modifiers == [.control, .option])
        #expect(GlobalShortcut.defaultShortcut.displayString == "⌃⌥W")
        #expect(GlobalShortcut(keyCode: 0, modifiers: []) == nil)
        #expect(GlobalShortcut(keyCode: 0, modifiers: [.shift]) == nil)
        #expect(GlobalShortcut(keyCode: 49, modifiers: [.command]) == nil)
        #expect(GlobalShortcut(keyCode: 0, modifiers: .init(rawValue: 1 << 12)) == nil)
        #expect(GlobalShortcut(keyCode: 44, modifiers: [.control, .option, .shift, .command])?.displayString == "⌃⌥⇧⌘/")
    }

    @Test func shortcutPreferencesRoundTripAndRestoreDefault() throws {
        let suite = "PhotosWallpaperTests.Shortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalShortcutSettingsStore(defaults: defaults)
        #expect(store.load() == .defaultShortcut)
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.control, .command, .shift]))
        store.save(custom)
        #expect(GlobalShortcutSettingsStore(defaults: defaults).load() == custom)
        store.save(.defaultShortcut)
        #expect(GlobalShortcutSettingsStore(defaults: defaults).load() == .defaultShortcut)
    }

    @Test func malformedShortcutPreferencesFallBackToDefault() throws {
        let suite = "PhotosWallpaperTests.Shortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalShortcutSettingsStore(defaults: defaults)
        defaults.set(1, forKey: "GlobalShortcut.Modifiers")
        for value: Any in ["2", true, 2.5, -1, 999, [2], UInt64.max] {
            defaults.set(value, forKey: "GlobalShortcut.KeyCode")
            #expect(store.load() == .defaultShortcut)
        }
        defaults.set(2, forKey: "GlobalShortcut.KeyCode")
        for value: Any in ["1", true, 1.5, -1, 0, [1], UInt64.max] {
            defaults.set(value, forKey: "GlobalShortcut.Modifiers")
            #expect(store.load() == .defaultShortcut)
        }
    }
}
