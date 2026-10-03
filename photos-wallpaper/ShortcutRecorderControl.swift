// Adapted from MacClipboardDiff. Copyright (c) 2026 stuartd. MIT license; see LICENSE.
import AppKit
import Foundation

final class ShortcutRecorderControl: NSView {
    var shortcut = GlobalShortcut.defaultShortcut {
        didSet {
            setAccessibilityValue(shortcut.displayString)
            needsDisplay = true
        }
    }
    var accessibilityShortcutLabel = "Keyboard shortcut" {
        didSet { setAccessibilityLabel(accessibilityShortcutLabel) }
    }
    var onChange: ((GlobalShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityShortcutLabel)
        setAccessibilityValue(shortcut.displayString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.initialFirstResponder = self
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !capture(event) {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event) || super.performKeyEquivalent(with: event)
    }

    @discardableResult
    func record(_ newShortcut: GlobalShortcut) -> Bool {
        guard window?.firstResponder === self else { return false }
        shortcut = newShortcut
        onChange?(newShortcut)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor)
            .setStroke()
        path.lineWidth = window?.firstResponder === self ? 2 : 1
        path.stroke()

        // Measure each key separately so wide modifier glyphs have a real gap.
        let keys = shortcut.displayString.map { String($0) as NSString }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let sizes = keys.map { $0.size(withAttributes: attributes) }
        let spacing: CGFloat = 10
        let totalWidth = sizes.reduce(0) { $0 + $1.width }
            + spacing * CGFloat(max(0, keys.count - 1))
        var x = floor((self.bounds.width - totalWidth) / 2)

        for (key, size) in zip(keys, sizes) {
            key.draw(
                at: NSPoint(x: x, y: floor((self.bounds.height - size.height) / 2)),
                withAttributes: attributes
            )
            x += size.width + spacing
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        // AppKit sends key equivalents throughout the view hierarchy, including
        // views that do not currently have keyboard focus.
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        guard let newShortcut = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        ) else {
            return false
        }

        return record(newShortcut)
    }
}
