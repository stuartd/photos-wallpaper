// Adapted from MacClipboardDiff. Copyright (c) 2026 stuartd. MIT license; see LICENSE.
import AppKit
import Carbon
import Foundation

enum GlobalShortcutError: Error, Equatable, LocalizedError {
    case requiresOptionOrControl
    case systemShortcut
    case menuItem(String)
    case systemCheckFailed(OSStatus)
    case keyboardLayoutUnavailable
    case alreadyRegistered
    case registrationFailed(OSStatus)
    case eventHandlerFailed(OSStatus)
    case unavailable

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .requiresOptionOrControl:
            return "Include Option or Control so this shortcut doesn’t replace common app commands. You can also include Command and Shift."
        case .systemShortcut:
            return "macOS already uses this shortcut. Choose another, or change it in System Settings → Keyboard → Keyboard Shortcuts."
        case .menuItem(let title):
            return "This shortcut is already used by “\(title)” in Photos Wallpaper’s menus. Choose another one."
        case .systemCheckFailed(let status):
            return "Couldn’t check macOS keyboard shortcuts. Try again. (macOS error \(status))"
        case .keyboardLayoutUnavailable:
            return "Couldn’t read the keyboard layout to check menu shortcuts. Try again."
        case .alreadyRegistered:
            return "Another app has registered this shortcut. Choose another one."
        case .registrationFailed(let status):
            return "macOS couldn’t register this shortcut (error \(status)). Choose another one."
        case .eventHandlerFailed(let status):
            return "Photos Wallpaper couldn’t listen for keyboard shortcuts (macOS error \(status)). Try reopening Photos Wallpaper."
        case .unavailable:
            return "Photos Wallpaper’s keyboard shortcut listener is unavailable. Try reopening Photos Wallpaper."
        }
    }

    static func registrationFailure(_ status: OSStatus) -> Self {
        status == eventHotKeyExistsErr ? .alreadyRegistered : .registrationFailed(status)
    }
}

@MainActor
struct GlobalShortcutValidator {
    struct SystemShortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        let isEnabled: Bool
    }

    // Providers keep tests independent of the user's system settings and menus.
    var systemShortcuts: () -> Result<[SystemShortcut], GlobalShortcutError>
    var mainMenu: () -> NSMenu?
    var characters: (GlobalShortcut, Bool) -> String?
    var isShortcutItem: (NSMenuItem) -> Bool

    init(
        systemShortcuts: (() -> Result<[SystemShortcut], GlobalShortcutError>)? = nil,
        mainMenu: (() -> NSMenu?)? = nil,
        characters: ((GlobalShortcut, Bool) -> String?)? = nil,
        isShortcutItem: @escaping (NSMenuItem) -> Bool = { _ in false }
    ) {
        self.systemShortcuts = systemShortcuts ?? Self.readSystemShortcuts
        self.mainMenu = mainMenu ?? { NSApp?.mainMenu }
        self.characters = characters ?? Self.keyboardCharacters
        self.isShortcutItem = isShortcutItem
    }

    func error(for shortcut: GlobalShortcut) -> GlobalShortcutError? {
        // Command and Command-Shift combinations commonly belong to other
        // apps' menus, which macOS's system shortcut list does not include.
        guard !shortcut.modifiers.intersection([.option, .control]).isEmpty else {
            return .requiresOptionOrControl
        }

        switch systemShortcuts() {
        case .failure(let error):
            return error
        case .success(let shortcuts):
            if shortcuts.contains(where: {
                $0.isEnabled && $0.keyCode == shortcut.keyCode
                    && $0.modifiers == shortcut.carbonModifiers
            }) {
                return .systemShortcut
            }
        }

        guard let menu = mainMenu() else { return nil }
        guard let base = characters(shortcut, false) else {
            return .keyboardLayoutUnavailable
        }
        let shifted = shortcut.modifiers.contains(.shift) ? characters(shortcut, true) : nil
        return conflictingItem(in: menu, shortcut: shortcut, base: base, shifted: shifted)
            .map { .menuItem($0.title) }
    }

    private func conflictingItem(
        in menu: NSMenu,
        shortcut: GlobalShortcut,
        base: String,
        shifted: String?
    ) -> NSMenuItem? {
        for item in menu.items {
            var equivalent = item.keyEquivalent
            var modifiers = item.keyEquivalentModifierMask
            if equivalent != equivalent.lowercased() {
                equivalent = equivalent.lowercased()
                modifiers.insert(.shift)
            }

            // Disabled commands still own their shortcuts when they become enabled.
            if !isShortcutItem(item), !equivalent.isEmpty {
                if equivalent == base.lowercased(), modifiers == shortcut.appKitModifiers {
                    return item
                }
                // AppKit can encode Shift in punctuation itself, for example “?”.
                if let shifted, shifted != base, equivalent == shifted,
                   modifiers.subtracting(.shift) == shortcut.appKitModifiers.subtracting(.shift) {
                    return item
                }
            }
            if let submenu = item.submenu,
               let conflict = conflictingItem(in: submenu, shortcut: shortcut, base: base, shifted: shifted) {
                return conflict
            }
        }
        return nil
    }

    private static func readSystemShortcuts() -> Result<[SystemShortcut], GlobalShortcutError> {
        var values: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&values)
        let array = values?.takeRetainedValue()
        guard status == noErr else { return .failure(.systemCheckFailed(status)) }
        let dictionaries = array as? [[String: Any]] ?? []
        return .success(dictionaries.compactMap { value in
            guard let key = value[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = value[kHISymbolicHotKeyModifiers as String] as? NSNumber,
                  let enabled = value[kHISymbolicHotKeyEnabled as String] as? NSNumber else {
                return nil
            }
            return SystemShortcut(
                keyCode: key.uint32Value,
                modifiers: modifiers.uint32Value,
                isEnabled: enabled.boolValue
            )
        })
    }

    static func keyboardCharacters(_ shortcut: GlobalShortcut, shifted: Bool) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            UInt16(shortcut.keyCode),
            UInt16(kUCKeyActionDisplay),
            shifted ? UInt32(shiftKey >> 8) : 0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

extension GlobalShortcut {
    func matches(_ event: NSEvent) -> Bool {
        event.type == .keyDown && UInt32(event.keyCode) == keyCode
            && event.modifierFlags.intersection([.control, .option, .command, .shift]) == appKitModifiers
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var appKitModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}
