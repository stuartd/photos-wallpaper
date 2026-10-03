import Carbon
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func hotKeyStartupConflictCanBeRetried() {
        let backend = FakeHotKeyBackend()
        var conflict: GlobalShortcutError? = .systemShortcut
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend,
                                                validate: { _ in conflict }, action: {})
        #expect(!controller.isRegistered)
        #expect(controller.lastError == conflict)
        #expect(backend.events == ["install"])
        conflict = nil
        #expect(controller.updateShortcut(.defaultShortcut))
        #expect(controller.isRegistered)
        #expect(controller.lastError == nil)
    }

    @Test func hotKeyFailedReplacementKeepsWorkingShortcut() throws {
        let backend = FakeHotKeyBackend()
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        backend.error = .alreadyRegistered
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.command, .option]))
        #expect(!controller.updateShortcut(custom))
        #expect(controller.isRegistered)
        #expect(controller.registeredShortcut == .defaultShortcut)
        #expect(controller.lastError == .alreadyRegistered)
        #expect(backend.events == ["install", "register", "register"])

        backend.error = nil
        #expect(controller.updateShortcut(custom))
        #expect(controller.registeredShortcut == custom)
        #expect(backend.events == ["install", "register", "register", "register", "unregister:1"])
    }

    @Test func hotKeySavingCurrentChoiceRevalidatesWithoutRegisteringAgain() {
        let backend = FakeHotKeyBackend()
        var conflict: GlobalShortcutError?
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend,
                                                validate: { _ in conflict }, action: {})
        backend.error = .alreadyRegistered
        #expect(controller.updateShortcut(.defaultShortcut))
        #expect(backend.events == ["install", "register"])
        conflict = .systemShortcut
        #expect(!controller.updateShortcut(.defaultShortcut))
        #expect(controller.isRegistered)
        #expect(controller.lastError == conflict)
        #expect(backend.events == ["install", "register"])
    }

    @Test func hotKeyMenuTrackingRestoresLatestShortcut() throws {
        let backend = FakeHotKeyBackend()
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        let custom = try #require(GlobalShortcut(keyCode: 2, modifiers: [.command, .option]))
        #expect(controller.updateShortcut(custom))
        controller.setMenuTracking(true)
        #expect(!controller.isRegistered)
        controller.setMenuTracking(false)
        #expect(controller.isRegistered)
        #expect(backend.shortcuts == [.defaultShortcut, custom, custom])
        #expect(backend.events == ["install", "register", "register", "unregister:1", "unregister:2", "register"])
    }

    @Test func hotKeyMenuRestoreFailureCanRecover() {
        let backend = FakeHotKeyBackend()
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        controller.setMenuTracking(true)
        backend.error = .alreadyRegistered
        controller.setMenuTracking(false)
        #expect(!controller.isRegistered)
        #expect(controller.lastError == .alreadyRegistered)
        backend.error = nil
        #expect(controller.updateShortcut(.defaultShortcut))
        #expect(controller.isRegistered)
    }

    @Test func hotKeyHandlerFailurePreventsRegistration() {
        let backend = FakeHotKeyBackend()
        backend.installStatus = -50
        let controller = GlobalHotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        #expect(!controller.isRegistered)
        #expect(controller.lastError == .eventHandlerFailed(-50))
        #expect(backend.events == ["install"])
        #expect(!controller.updateShortcut(.defaultShortcut))
    }

    @Test func hotKeyShutdownReleasesRegistration() {
        let backend = FakeHotKeyBackend()
        var controller: GlobalHotKeyController? = GlobalHotKeyController(
            shortcut: .defaultShortcut, backend: backend, action: {})
        #expect(controller?.isRegistered == true)
        controller = nil
        #expect(backend.events == ["install", "register", "unregister:1"])
    }

    @Test func hotKeyErrorsDistinguishConflictsFromOtherFailures() {
        #expect(GlobalShortcutError.registrationFailure(OSStatus(eventHotKeyExistsErr)) == .alreadyRegistered)
        #expect(GlobalShortcutError.registrationFailure(-50) == .registrationFailed(-50))
    }
}

/// Records registration order without touching Carbon or reserving a real shortcut.
@MainActor
final class FakeHotKeyBackend: HotKeyBackend {
    var events: [String] = []
    var shortcuts: [GlobalShortcut] = []
    var installStatus: OSStatus = noErr
    var error: GlobalShortcutError?
    var action: (() -> Void)?
    private var nextReference = 1

    func installEventHandler(action: @escaping () -> Void) -> OSStatus {
        events.append("install")
        self.action = action
        return installStatus
    }

    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError> {
        events.append("register")
        shortcuts.append(shortcut)
        if let error { return .failure(error) }
        defer { nextReference += 1 }
        return .success(OpaquePointer(bitPattern: nextReference)!)
    }

    nonisolated func unregister(_ reference: EventHotKeyRef) {
        MainActor.assumeIsolated {
            events.append("unregister:\(Int(bitPattern: reference))")
        }
    }
}
