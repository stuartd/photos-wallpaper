// Adapted from MacClipboardDiff. Copyright (c) 2026 stuartd. MIT license; see LICENSE.
import Carbon
import Foundation

private let photosWallpaperHotKeySignature: OSType = 0x5057504B
private let photosWallpaperHotKeyIdentifier: UInt32 = 1

@MainActor
protocol HotKeyBackend: AnyObject {
    func installEventHandler(action: @escaping () -> Void) -> OSStatus
    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError>
    nonisolated func unregister(_ reference: EventHotKeyRef)
}

@MainActor
final class GlobalHotKeyController {
    private let backend: HotKeyBackend
    private let validate: (GlobalShortcut) -> GlobalShortcutError?
    private var hotKeyRef: EventHotKeyRef?
    private let eventHandlerStatus: OSStatus
    private var isMenuTracking = false
    private var shortcut: GlobalShortcut

    var isRegistered: Bool { hotKeyRef != nil }
    private(set) var registeredShortcut: GlobalShortcut?
    private(set) var lastError: GlobalShortcutError?

    init(
        shortcut: GlobalShortcut,
        backend: HotKeyBackend? = nil,
        validate: @escaping (GlobalShortcut) -> GlobalShortcutError? = { _ in nil },
        action: @escaping () -> Void
    ) {
        let backend = backend ?? CarbonHotKeyBackend()
        self.shortcut = shortcut
        self.backend = backend
        self.validate = validate
        eventHandlerStatus = backend.installEventHandler(action: action)
        updateShortcut(shortcut)
    }

    deinit {
        if let hotKeyRef {
            backend.unregister(hotKeyRef)
        }
    }

    func setMenuTracking(_ isTracking: Bool) {
        isMenuTracking = isTracking
        if isTracking {
            if let hotKeyRef {
                backend.unregister(hotKeyRef)
                self.hotKeyRef = nil
            }
        } else if hotKeyRef == nil {
            if !updateShortcut(shortcut) {
                debugLog("GlobalHotKeyController: could not restore shortcut after menu tracking: \(lastError?.message ?? "Unknown error")")
            }
        }
    }

    @discardableResult
    func updateShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard eventHandlerStatus == noErr else {
            lastError = .eventHandlerFailed(eventHandlerStatus)
            return false
        }
        // Startup and replacement must use the same checks. Recheck even when
        // saving the current shortcut, since system settings may have changed.
        if let error = validate(shortcut) {
            lastError = error
            return false
        }
        if hotKeyRef != nil, registeredShortcut == shortcut {
            lastError = nil
            return true
        }

        // Keep the old registration until macOS accepts its replacement.
        switch backend.register(shortcut) {
        case .success(let reference):
            if let hotKeyRef {
                backend.unregister(hotKeyRef)
            }
            hotKeyRef = reference
            self.shortcut = shortcut
            if isMenuTracking {
                backend.unregister(reference)
                hotKeyRef = nil
            }
            registeredShortcut = shortcut
            lastError = nil
            return true
        case .failure(let error):
            lastError = error
            return false
        }
    }
}

@MainActor
final class CarbonHotKeyBackend: HotKeyBackend {
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func installEventHandler(action: @escaping () -> Void) -> OSStatus {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let backend = Unmanaged<CarbonHotKeyBackend>
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

                // Carbon dispatches on the main thread, including inside the modal picker.
                MainActor.assumeIsolated { backend.action?() }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError> {
        let hotKeyID = EventHotKeyID(
            signature: photosWallpaperHotKeySignature,
            id: photosWallpaperHotKeyIdentifier
        )

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )

        guard status == noErr, let reference else {
            return .failure(.registrationFailure(status == noErr ? OSStatus(eventInternalErr) : status))
        }
        return .success(reference)
    }

    nonisolated func unregister(_ reference: EventHotKeyRef) {
        UnregisterEventHotKey(reference)
    }
}
