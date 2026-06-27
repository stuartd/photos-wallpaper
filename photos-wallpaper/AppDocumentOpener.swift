import Foundation
import AppKit

protocol AppDocumentOpening {
    func openAboutPanel()
    func openPrivacyDocument()
    func openSupportPage()
}

protocol ExternalURLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: ExternalURLOpening {}

final class AppDocumentOpener: AppDocumentOpening {
    private static let supportURL = URL(string: "https://photos-wallpaper.app/#support")!

    // Keep a strong reference to the window so it isn't deallocated immediately
    private var privacyWindow: NSWindow?
    private var privacyWindowCloseObserver: NSObjectProtocol?
    private let urlOpener: ExternalURLOpening

    init(urlOpener: ExternalURLOpening = NSWorkspace.shared) {
        self.urlOpener = urlOpener
    }

    deinit {
        clearPrivacyWindowCloseObserver()
    }

    func openAboutPanel() {
        let iconView = NSImageView(image: appIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: "Photos Wallpaper")
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: aboutVersionText)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        // Blank lines to put this in the centre of the dialog
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

    private var appIconImage: NSImage {
        NSImage(named: "AppIcon")
            ?? Bundle.main.image(forResource: "AppIcon")
            ?? NSApp.applicationIconImage
    }

    func openPrivacyDocument() {
        if let privacyWindow {
            privacyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        privacyWindowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.privacyWindow = nil
            self?.clearPrivacyWindowCloseObserver()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSupportPage() {
        guard urlOpener.open(Self.supportURL) else {
            debugLog("AppDocumentOpener: failed to open support URL \(Self.supportURL.absoluteString)")
            return
        }
    }

    private var aboutVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        var details: [String] = []
        if let build,
           !build.isEmpty,
           !build.hasPrefix("$(") {
            details.append("build \(build)")
        }
        if let commit = Bundle.main.object(forInfoDictionaryKey: "GitCommit") as? String,
           !commit.isEmpty,
           !commit.hasPrefix("$(") {
            details.append("commit \(commit)")
        }
        #if DEBUG
        details.append("debug build")
        #endif

        guard !details.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(details.joined(separator: ", ")))"
    }

    private func clearPrivacyWindowCloseObserver() {
        if let privacyWindowCloseObserver {
            NotificationCenter.default.removeObserver(privacyWindowCloseObserver)
            self.privacyWindowCloseObserver = nil
        }
    }

    private func makePrivacyAttributedString(from markdownText: String) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for rawLine in markdownText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                output.append(NSAttributedString(string: "\n"))
            } else if line.hasPrefix("# ") {
                output.append(markdownLine(String(line.dropFirst(2)), font: .boldSystemFont(ofSize: 26), paragraphSpacing: 14))
            } else if line.hasPrefix("## ") {
                output.append(markdownLine(String(line.dropFirst(3)), font: .boldSystemFont(ofSize: 18), paragraphSpacing: 10))
            } else if line.hasPrefix("- ") {
                output.append(markdownLine("• " + line.dropFirst(2), font: .preferredFont(forTextStyle: .body), paragraphSpacing: 4))
            } else if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                output.append(markdownLine(line, font: .preferredFont(forTextStyle: .body), paragraphSpacing: 4))
            } else {
                output.append(markdownLine(line, font: .preferredFont(forTextStyle: .body), paragraphSpacing: 8))
            }
        }

        return output
    }

    private func markdownLine(_ line: String, font: NSFont, paragraphSpacing: CGFloat) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let parsed = (try? NSMutableAttributedString(
            markdown: Data(line.utf8),
            options: options
        )) ?? NSMutableAttributedString(string: line)
        let fullRange = NSRange(location: 0, length: parsed.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.lineSpacing = 2

        parsed.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)
        parsed.append(NSAttributedString(string: "\n"))
        return parsed
    }
}
