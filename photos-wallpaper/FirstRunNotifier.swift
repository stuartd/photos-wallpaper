import Foundation
import AppKit

protocol FirstRunWelcomePresenting {
    func presentMenuBarWelcome()
    func dismissMenuBarWelcome()
}

final class AppKitFirstRunWelcomePresenter: NSObject, FirstRunWelcomePresenting {
    private var panel: NSPanel?
    private var panelCloseObserver: NSObjectProtocol?

    deinit {
        clearPanelCloseObserver()
    }

    func presentMenuBarWelcome() {
        if let panel {
            debugLog("FirstRunNotifier: welcome panel already exists; bringing it forward.")
            bringToFront(panel)
            return
        }

        debugLog("FirstRunNotifier: creating menu bar welcome panel.")

        let iconView = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                                   ?? NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: "Photos Wallpaper is in the menu bar")
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.alignment = .center

        let bodyLabel = NSTextField(wrappingLabelWithString: "Look for the photo icon in the menu bar to change your wallpaper schedule, run a change now, or open logs.")
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 0

        let button = NSButton(title: "Got it", target: self, action: #selector(closeWelcomePanel))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [iconView, titleLabel, bodyLabel, button])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            bodyLabel.widthAnchor.constraint(equalToConstant: 310),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 210),
                            styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.title = "Photos Wallpaper"
        panel.contentView = contentView
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        self.panel = panel
        panelCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                    object: panel,
                                                                    queue: .main) { [weak self] _ in
            self?.panel = nil
            self?.clearPanelCloseObserver()
        }

        bringToFront(panel)
        debugLog("FirstRunNotifier: showed menu bar welcome panel.")
    }

    func dismissMenuBarWelcome() {
        panel?.close()
    }

    @objc private func closeWelcomePanel() {
        panel?.close()
    }

    private func clearPanelCloseObserver() {
        if let panelCloseObserver {
            NotificationCenter.default.removeObserver(panelCloseObserver)
            self.panelCloseObserver = nil
        }
    }

    private func bringToFront(_ panel: NSPanel) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class FirstRunNotifier {
    private static let didShowMenuBarWelcomeDefaultsKey = "didShowMenuBarWelcomeWindow"

    private let defaults: KeyValueStoring
    private let presenter: FirstRunWelcomePresenting

    init(defaults: KeyValueStoring = UserDefaults.standard,
         presenter: FirstRunWelcomePresenting? = nil) {
        self.defaults = defaults
        self.presenter = presenter ?? AppKitFirstRunWelcomePresenter()
    }

    func notifyIfNeeded() {
        guard !defaults.bool(forKey: Self.didShowMenuBarWelcomeDefaultsKey) else {
            debugLog("FirstRunNotifier: menu bar welcome panel already shown.")
            return
        }

        defaults.set(true, forKey: Self.didShowMenuBarWelcomeDefaultsKey)
        debugLog("FirstRunNotifier: marking menu bar welcome panel as shown.")
        presenter.presentMenuBarWelcome()
    }

    func dismissWelcomeIfPresented() {
        presenter.dismissMenuBarWelcome()
    }
}
