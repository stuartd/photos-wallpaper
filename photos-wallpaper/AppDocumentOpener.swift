import Foundation
import AppKit

protocol AppDocumentOpening {
    func openPrivacyDocument()
}

final class AppDocumentOpener: AppDocumentOpening {
    // Keep a strong reference to the window so it isn't deallocated immediately
    private var privacyWindow: NSWindow?

    func openPrivacyDocument() {
        // Locate the PRIVACY.md in the app bundle
        guard let privacyURL = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") else {
            debugLog("AppDocumentOpener: PRIVACY.md not found in bundle")
            return
        }

        // Attempt to load the markdown text
        guard let markdownText = try? String(contentsOf: privacyURL, encoding: .utf8) else {
            debugLog("AppDocumentOpener: failed to load PRIVACY.md contents")
            return
        }

        // Convert markdown to attributed string (monterey+). If conversion fails, fall back to plain text.
        let attributed: NSAttributedString
        if let md = try? AttributedString(markdown: markdownText) {
            attributed = NSAttributedString(md)
        } else {
            attributed = NSAttributedString(string: markdownText)
        }

        // Create and present a simple read-only window with scrollable text view
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textStorage?.setAttributedString(attributed)
        textView.drawsBackground = true

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentViewController = NSViewController()
        contentViewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 800))
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentViewController.view.addSubview(scrollView)

        // Pin scroll view to edges
        scrollView.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor).isActive = true
        scrollView.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor).isActive = true
        scrollView.topAnchor.constraint(equalTo: contentViewController.view.topAnchor).isActive = true
        scrollView.bottomAnchor.constraint(equalTo: contentViewController.view.bottomAnchor).isActive = true

        let window = NSWindow(contentViewController: contentViewController)
        window.title = "Privacy Policy"
        window.setContentSize(NSSize(width: 700, height: 800))
        window.center()
        window.isReleasedWhenClosed = false

        // Retain the window while shown
        self.privacyWindow = window

        // Observe close to release our reference
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            if self?.privacyWindow === window {
                self?.privacyWindow = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
