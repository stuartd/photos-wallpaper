import Carbon
import Foundation

private let photosWallpaperHotKeySignature: OSType = 0x5057504B // "PWPK"
private let photosWallpaperHotKeyIdentifier: UInt32 = 1

/// Registers the app's shortcut with macOS so it works while another app is active.
///
/// SwiftUI's `keyboardShortcut` displays and handles the shortcut in the menu, but menu bar apps
/// also need a Carbon hot key registration to receive it globally.
final class GlobalHotKeyController {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void

    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        installEventHandler()
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }
                guard hotKeyID.signature == photosWallpaperHotKeySignature,
                      hotKeyID.id == photosWallpaperHotKeyIdentifier else {
                    return noErr
                }

                controller.action()
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(
            signature: photosWallpaperHotKeySignature,
            id: photosWallpaperHotKeyIdentifier
        )
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        isRegistered = status == noErr
    }
}
