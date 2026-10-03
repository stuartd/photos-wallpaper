import AppKit
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func shortcutRecorderCapturesOnlyWhenFocusedAndAcceptsCurrentBinding() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView()
        let recorder = ShortcutRecorderControl()
        let other = ShortcutFocusTarget()
        content.addSubview(recorder)
        content.addSubview(other)
        window.contentView = content
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2))
        var recordings: [GlobalShortcut] = []
        recorder.onChange = { recordings.append($0) }

        #expect(window.makeFirstResponder(other))
        #expect(!recorder.performKeyEquivalent(with: event))
        #expect(recordings.isEmpty)
        #expect(window.makeFirstResponder(recorder))
        #expect(recorder.performKeyEquivalent(with: event))
        #expect(recordings == [GlobalShortcut(keyCode: 2, modifiers: [.command])!])
        #expect(recorder.record(.defaultShortcut))
        #expect(recordings.last == .defaultShortcut)
        #expect(window.makeFirstResponder(other))
        #expect(!recorder.record(.defaultShortcut))
        #expect(recordings.count == 2)
    }
}

@MainActor
private final class ShortcutFocusTarget: NSView {
    override var acceptsFirstResponder: Bool { true }
}
