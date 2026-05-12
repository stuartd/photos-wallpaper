import Foundation
import AppKit

protocol AppDocumentOpening {
    func openAboutPanel()
    func openPrivacyDocument()
}

final class AppDocumentOpener: AppDocumentOpening {
    // Keep a strong reference to the window so it isn't deallocated immediately
    private var privacyWindow: NSWindow?

    func openAboutPanel() {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: "Photos Wallpaper")
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: "Version 1.0")
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        
        // TODO - properly, not just blank lines

        let creditsLabel = NSTextField(wrappingLabelWithString: """
        © Stuart Dunkeld 2026
        Rose Hill Solutions
        
        
        
        
        
        """)

        creditsLabel.font = .systemFont(ofSize: 13)
        creditsLabel.alignment = .center
        creditsLabel.maximumNumberOfLines = 0

        let stackView = NSStackView(views: [iconView, titleLabel, versionLabel, creditsLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 205))
        accessoryView.addSubview(stackView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 128),
            iconView.heightAnchor.constraint(equalToConstant: 128),
            creditsLabel.widthAnchor.constraint(equalToConstant: 300),
            stackView.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualTo: accessoryView.widthAnchor)
        ])

        let alert = NSAlert()
        alert.messageText = ""
        alert.informativeText = ""
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        alert.accessoryView = accessoryView
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

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

        let attributed = makePrivacyAttributedString(from: markdownText)

        // Create and present a simple read-only window with scrollable text view
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 800))
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textStorage?.setAttributedString(attributed)
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

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

    private func makePrivacyAttributedString(from markdownText: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let bodyFont = NSFont.preferredFont(forTextStyle: .body)
        let bodyColor = NSColor.labelColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineSpacing = 2

        for rawLine in markdownText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            let text: String
            let font: NSFont
            let paragraphSpacing: CGFloat

            if line.hasPrefix("# ") {
                text = String(line.dropFirst(2))
                font = NSFont.boldSystemFont(ofSize: 26)
                paragraphSpacing = 14
            } else if line.hasPrefix("## ") {
                text = String(line.dropFirst(3))
                font = NSFont.boldSystemFont(ofSize: 18)
                paragraphSpacing = 10
            } else if line.hasPrefix("- ") {
                text = "• " + line.dropFirst(2)
                font = bodyFont
                paragraphSpacing = 4
            } else {
                text = line
                font = bodyFont
                paragraphSpacing = 8
            }

            let style = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.paragraphSpacing = paragraphSpacing

            output.append(NSAttributedString(
                string: text.replacingOccurrences(of: "`", with: "") + "\n",
                attributes: [
                    .font: font,
                    .foregroundColor: bodyColor,
                    .paragraphStyle: style
                ]
            ))
        }

        return output
    }
}
