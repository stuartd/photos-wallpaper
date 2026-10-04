import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

/// Coordinates the persisted choice, global registration, and menu presentation.
@MainActor
final class WallpaperShortcutController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    let menuAppearance: MenuShortcutAppearance
    private let settingsStore: GlobalShortcutSettingsStore
    private let validator: GlobalShortcutValidator
    private var hotKeyController: GlobalHotKeyController?
    private var inputSourceObserver: NSObjectProtocol?
    private var settingsWindowController: ShortcutSettingsWindowController?

    init(
        menuTitle: String,
        defaults: UserDefaults = .standard,
        backend: HotKeyBackend? = nil,
        validator: GlobalShortcutValidator? = nil,
        notificationCenter: NotificationCenter = .default,
        action: @escaping () -> Void
    ) {
        let store = GlobalShortcutSettingsStore(defaults: defaults)
        let initialShortcut = store.load()
        let validator = validator ?? GlobalShortcutValidator(isShortcutItem: { $0.title == menuTitle })
        settingsStore = store
        self.validator = validator
        shortcut = initialShortcut
        menuAppearance = MenuShortcutAppearance(title: menuTitle, shortcut: initialShortcut,
                                                notificationCenter: notificationCenter,
                                                activateShortcut: action)
        hotKeyController = GlobalHotKeyController(
            shortcut: initialShortcut, backend: backend,
            validate: { validator.error(for: $0) }
        ) { [weak self] in
            guard let self else { return }
            // Carbon consumes the current binding before AppKit can record it.
            if self.settingsWindowController?.captureRegisteredShortcut(self.shortcut) == true {
                return
            }
            self.menuAppearance.activateShortcut()
        }
        menuAppearance.menuTrackingChanged = { [weak self] isTracking in
            self?.hotKeyController?.setMenuTracking(isTracking)
        }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.menuAppearance.updateShortcut(self.shortcut)
                self.settingsWindowController?.refreshKeyboardLayout()
            }
        }
        if let error = hotKeyController?.lastError {
            debugLog("WallpaperShortcutController: \(error.message)")
        }
    }

    deinit {
        if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = ShortcutSettingsWindowController(
                currentShortcut: { [weak self] in self?.shortcut ?? .defaultShortcut },
                accessibilityLabel: "\(photos_wallpaperApp.changeWallpaperMenuTitle) keyboard shortcut",
                initialError: { [weak self] in self?.hotKeyController?.lastError },
                validate: { [validator] in validator.error(for: $0) },
                save: { [weak self] shortcut in
                    guard let self else { return .unavailable }
                    return self.setShortcut(shortcut)
                }
            )
        }
        settingsWindowController?.show()
    }

    @discardableResult
    func setShortcut(_ shortcut: GlobalShortcut) -> GlobalShortcutError? {
        guard hotKeyController?.updateShortcut(shortcut) == true else {
            return hotKeyController?.lastError ?? .unavailable
        }
        self.shortcut = shortcut
        settingsStore.save(shortcut)
        menuAppearance.updateShortcut(shortcut)
        return nil
    }
}

extension GlobalShortcut {
    var swiftUIModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    var keyEquivalent: KeyEquivalent {
        keyEquivalent { _ in GlobalShortcutValidator.keyboardCharacters(self, shifted: false) }
    }

    func keyEquivalent(using characters: (UInt32) -> String?) -> KeyEquivalent {
        // Validated key codes always have a nonempty fallback label, even without a keyboard layout.
        KeyEquivalent(keyEquivalentCharacters(using: characters).first!)
    }
}
