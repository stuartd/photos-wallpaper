import AppKit
import Carbon

/// Changes only the drawing of a SwiftUI-created menu item. Its native key equivalent, target,
/// and action stay in place so AppKit can still activate it while the menu is tracking.
@MainActor
final class MenuShortcutAppearance {
    private let title: String
    private let shortcut: String
    private let action: () -> Void
    private weak var shortcutItem: NSMenuItem?
    private var trackingMenus: [NSMenu] = []
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var isPreparing = false
    private var keyMonitor: Any?
    private var trackingObserver: CFRunLoopObserver?
    private var isReadingEvents = false
    var menuTrackingChanged: (Bool) -> Void = { _ in }

    init(title: String, shortcut: String, notificationCenter: NotificationCenter = .default,
         activateShortcut: @escaping () -> Void = {}) {
        self.title = title
        self.shortcut = shortcut
        self.action = activateShortcut
        self.notificationCenter = notificationCenter
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.trackingMenus.isEmpty,
                  self.matchesShortcut(event) else { return event }
            if !event.isARepeat { self.activateShortcut() }
            return nil
        }
        // SwiftUI can build or replace rows lazily. Install before layout when possible and
        // reconcile again on opening; do not replace SwiftUI's own NSMenuDelegate.
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                     NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(notificationCenter.addObserver(
                forName: name, object: nil, queue: nil
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let menu = notification.object as? NSMenu else { return }
                    guard let self else { return }
                    if notification.name == NSMenu.didEndTrackingNotification {
                        self.trackingMenus.removeAll { $0 === menu }
                        if self.trackingMenus.isEmpty { self.stopTrackingShortcut() }
                        return
                    }
                    self.prepare(menu)
                    if notification.name == NSMenu.didBeginTrackingNotification {
                        self.trackingMenus.append(menu)
                        self.startTrackingShortcut()
                    }
                }
            })
        }
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let trackingObserver { CFRunLoopObserverInvalidate(trackingObserver) }
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == UInt16(kVK_ANSI_W)
            && event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option]
    }

    private func startTrackingShortcut() {
        guard trackingObserver == nil else { return }
        // Carbon captures registered hotkeys before AppKit sees them, but menu tracking
        // can defer their delivery. Temporarily release the registration to receive W here.
        menuTrackingChanged(true)
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeSources.rawValue,
                                                         true, 0) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readTrackingEvents() }
        }
        trackingObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
    }

    private func stopTrackingShortcut() {
        guard let trackingObserver else { return }
        CFRunLoopObserverInvalidate(trackingObserver)
        self.trackingObserver = nil
        menuTrackingChanged(false)
    }

    private func readTrackingEvents() {
        guard !isReadingEvents, !trackingMenus.isEmpty else { return }
        isReadingEvents = true
        defer { isReadingEvents = false }
        var events: [NSEvent] = []
        while let event = NSApp.nextEvent(matching: .any, until: nil, inMode: .eventTracking, dequeue: true) {
            events.append(event)
        }
        let result = filterTrackingEvents(events)
        // Restore other input in its original order before invoking an action that can
        // close the menu or open another UI. Only the shortcut is consumed.
        for event in result.remaining.reversed() { NSApp.postEvent(event, atStart: true) }
        if result.shouldActivate { activateShortcut() }
    }

    func filterTrackingEvents(_ events: [NSEvent]) -> (remaining: [NSEvent], shouldActivate: Bool) {
        var shouldActivate = false
        let remaining = events.filter { event in
            guard matchesShortcut(event) else { return true }
            if !event.isARepeat { shouldActivate = true }
            return false
        }
        return (remaining, shouldActivate)
    }

    func activateShortcut() {
        // End AppKit's tracking loop synchronously, before the action creates any Tasks.
        // Main-actor work can otherwise remain queued until the user closes the menu.
        guard trackingMenus.isEmpty || shortcutItem?.isEnabled != false else { return }
        let menus = trackingMenus
        trackingMenus.removeAll()
        for menu in menus.reversed() {
            menu.cancelTracking()
        }
        stopTrackingShortcut()
        action()
    }

    func prepare(_ menu: NSMenu) {
        // Assigning a view can itself post an item-change notification.
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        prepareItems(in: menu)
    }

    private func prepareItems(in menu: NSMenu) {
        for item in menu.items {
            if item.title == title, !item.keyEquivalent.isEmpty {
                shortcutItem = item
                if let view = item.view as? MenuShortcutView {
                    view.bind(to: item)
                } else {
                    item.view = MenuShortcutView(item: item, shortcut: shortcut)
                }
            }
            if let submenu = item.submenu {
                prepareItems(in: submenu)
            }
        }
    }
}

/// AppKit still owns menu selection and keyboard dispatch. This view supplies the two text
/// columns and forwards mouse/accessibility activation to the original menu item's action.
@MainActor
final class MenuShortcutView: NSView {
    private weak var item: NSMenuItem?
    private let shortcut: String
    private let font: NSFont
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    // Custom views span the row, including the native checkmark gutter.
    private static let leadingInset: CGFloat = 30
    private static let trailingInset: CGFloat = 28
    private static let columnGap: CGFloat = 32

    init(item: NSMenuItem, shortcut: String) {
        self.item = item
        self.shortcut = shortcut
        font = item.menu?.font ?? NSFont.menuFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let titleSize = (item.title as NSString).size(withAttributes: attributes)
        let shortcutSize = (shortcut as NSString).size(withAttributes: attributes)
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: ceil(Self.leadingInset + titleSize.width + Self.columnGap
                        + shortcutSize.width + Self.trailingInset),
            height: ceil(max(titleSize.height, shortcutSize.height)) + 8
        ))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp(shortcut)
    }

    required init?(coder: NSCoder) {
        shortcut = coder.decodeObject(of: NSString.self, forKey: "shortcut") as String? ?? ""
        font = coder.decodeObject(of: NSFont.self, forKey: "menuFont") ?? NSFont.menuFont(ofSize: 0)
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(shortcut, forKey: "shortcut")
        coder.encode(font, forKey: "menuFont")
    }

    func bind(to item: NSMenuItem) {
        self.item = item
        setAccessibilityLabel(item.title)
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    // Draw the selection and its text without vibrancy so the wallpaper behind the
    // translucent menu cannot wash out the system selection colour.
    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let highlighted = item.isEnabled && (item.isHighlighted || isHovered)
        if highlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0),
                         xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = !item.isEnabled ? .disabledControlTextColor
            : highlighted ? .selectedMenuItemTextColor : .labelColor
        // Both columns deliberately share the same semantic colour in every state.
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let title = item.title as NSString
        let hint = shortcut as NSString
        let titleSize = title.size(withAttributes: attributes)
        let hintSize = hint.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: Self.leadingInset, y: (bounds.height - titleSize.height) / 2),
                   withAttributes: attributes)
        hint.draw(at: NSPoint(x: bounds.width - Self.trailingInset - hintSize.width,
                              y: (bounds.height - hintSize.height) / 2),
                  withAttributes: attributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let enclosingMenuItem {
            bind(to: enclosingMenuItem)
        }
        isHovered = false
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_ANSI_W),
              event.modifierFlags.contains([.control, .option]),
              event.modifierFlags.intersection([.command, .shift]) == [] else {
            return super.performKeyEquivalent(with: event)
        }
        return activate()
    }

    override func keyDown(with event: NSEvent) {
        if !performKeyEquivalent(with: event) {
            super.keyDown(with: event)
        }
    }

    override func isAccessibilityEnabled() -> Bool {
        item?.isEnabled == true
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
    }

    @discardableResult
    func activate() -> Bool {
        guard let item, item.isEnabled, let menu = item.menu else { return false }
        let index = menu.index(of: item)
        guard index >= 0 else { return false }
        menu.cancelTracking()
        menu.performActionForItem(at: index)
        return true
    }
}
