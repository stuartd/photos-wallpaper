// Adapted from MacClipboardDiff. Copyright (c) 2026 stuartd. MIT license; see LICENSE.
import CoreFoundation
import Foundation

struct GlobalShortcut: Equatable, Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        static let supported: Modifiers = [.command, .option, .control, .shift]
        static let required: Modifiers = [.command, .option, .control]
    }

    static let defaultShortcut = GlobalShortcut(
        keyCode: 13,
        modifiers: [.control, .option]
    )!

    let keyCode: UInt32
    let modifiers: Modifiers

    init?(keyCode: UInt32, modifiers: Modifiers) {
        guard Self.keyLabels[keyCode] != nil,
              modifiers.isSubset(of: .supported),
              !modifiers.intersection(.required).isEmpty else {
            return nil
        }

        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var keyLabel: String {
        Self.keyLabels[keyCode]!
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    private static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`"
    ]
}

struct GlobalShortcutSettingsStore {
    private enum Key {
        static let keyCode = "GlobalShortcut.KeyCode"
        static let modifiers = "GlobalShortcut.Modifiers"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GlobalShortcut {
        guard let keyCode = storedUInt32(forKey: Key.keyCode),
              let modifierBits = storedUInt32(forKey: Key.modifiers) else {
            return .defaultShortcut
        }
        let modifiers = GlobalShortcut.Modifiers(
            rawValue: modifierBits
        )
        return GlobalShortcut(keyCode: keyCode, modifiers: modifiers) ?? .defaultShortcut
    }

    func save(_ shortcut: GlobalShortcut) {
        defaults.set(Int(shortcut.keyCode), forKey: Key.keyCode)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: Key.modifiers)
    }

    private func storedUInt32(forKey key: String) -> UInt32? {
        // integer(forKey:) coerces strings, booleans and fractional values,
        // potentially turning corrupt preferences into an unrelated shortcut.
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return UInt32(exactly: number.doubleValue)
    }
}
