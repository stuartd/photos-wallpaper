import Foundation
import AppKit

protocol WallpaperHistoryLogging {
    func recordWallpaperChange(photoName: String, screenName: String, screenCount: Int, timestamp: Date)
    func openHistoryLog()
}

struct PhotoHistoryAssetDescriptionFormatter {
    private init() {}

    private static let localIdentifierRegex = try! NSRegularExpression(
        pattern: #"(?:^|,\s*)id:\s*(\S+)\s*$"#
    )

    static func string(filename: String, creationDate: Date?, localIdentifier: String, dateFormatter: DateFormatter) -> String {
        string(filename: filename,
               creationDateText: creationDate.map { dateFormatter.string(from: $0) },
               localIdentifier: localIdentifier)
    }

    static func string(filename: String, creationDateText: String?, localIdentifier: String) -> String {
        let identifierText = "id: \(localIdentifier)"
        if let creationDateText {
            return "\(filename) created \(creationDateText), \(identifierText)"
        }
        return "\(filename), \(identifierText)"
    }

    static func localIdentifier(in photoDescription: String) -> String? {
        let matchRange = NSRange(photoDescription.startIndex..., in: photoDescription)
        if let match = localIdentifierRegex.firstMatch(in: photoDescription, range: matchRange),
           let identifierRange = Range(match.range(at: 1), in: photoDescription) {
            return normalizedIdentifier(String(photoDescription[identifierRange]))
        }

        return normalizedIdentifier(photoDescription)
    }

    private static func normalizedIdentifier(_ identifier: String) -> String? {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return nil }
        guard trimmedIdentifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return trimmedIdentifier
    }
}

struct WallpaperHistoryEntryFormatter {
    private init() {}

    private static let identifierMarker = "id:"

    static func line(photoDescription: String, screenName: String, screenCount: Int, timestamp: Date, dateFormatter: DateFormatter) -> String {
        line(photoDescription: photoDescription,
             screenName: screenName,
             screenCount: screenCount,
             shownAtText: dateFormatter.string(from: timestamp))
    }

    static func line(photoDescription: String, screenName: String, screenCount: Int, shownAtText: String) -> String {
        let components = photoComponents(from: photoDescription)
        let screenText = screenCount > 1 ? " for \(screenName.lowercased())" : ""
        let detailsText = components.details.map { " (\($0))" } ?? ""
        return "Photo ID \(components.identifier) was set as the wallpaper\(screenText) on \(shownAtText)\(detailsText)"
    }

    private static func photoComponents(from photoDescription: String) -> (identifier: String, details: String?) {
        guard let markerRange = photoDescription.range(of: identifierMarker) else {
            return (identifier: photoDescription, details: nil)
        }

        let identifier = photoDescription[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let details = photoDescription[..<markerRange.lowerBound]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        return (identifier: identifier, details: details.isEmpty ? nil : details)
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    let text = message()
    AppRuntimeLogger.shared.record(text)

    #if DEBUG
    print(text)
    #endif
}

/// Appends to a plain-text log file and keeps only a bounded recent tail before it grows without bound.
final class BoundedLogFile {
    private let logURL: URL
    private let fileManager: FileManager
    private let maxSizeBytes: UInt64
    private let retainedLineCount: Int

    init(logURL: URL, fileManager: FileManager = .default, maxSizeBytes: UInt64, retainedLineCount: Int) {
        self.logURL = logURL
        self.fileManager = fileManager
        self.maxSizeBytes = maxSizeBytes
        self.retainedLineCount = retainedLineCount
    }

    func append(_ text: String) throws {
        try ensureLogFileExists()
        guard !text.isEmpty else { return }

        if let data = text.data(using: .utf8) {
            try trimIfNeeded(forAdditionalBytes: UInt64(data.count))
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }

    func ensureLogFileExists() throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    func reset() throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func trimIfNeeded(forAdditionalBytes additionalBytes: UInt64) throws {
        let currentSize = try currentLogSize()
        guard currentSize > 0, currentSize + additionalBytes > maxSizeBytes else { return }

        let retainedText = try retainedTailText()
        try retainedText.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func retainedTailText() throws -> String {
        guard retainedLineCount > 0 else { return "" }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" {
            lines.removeLast()
        }
        let retainedLines = lines.suffix(retainedLineCount)
        guard !retainedLines.isEmpty else { return "" }
        return retainedLines.joined(separator: "\n") + "\n"
    }

    private func currentLogSize() throws -> UInt64 {
        guard fileManager.fileExists(atPath: logURL.path) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        return attributes[.size] as? UInt64 ?? 0
    }
}

private enum AppLogStorage {
    static func directoryURL(fileManager: FileManager) -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return fileManager.temporaryDirectory
                .appendingPathComponent("photos-wallpaper-tests-\(getpid())", isDirectory: true)
                .appendingPathComponent("photos-wallpaper", isDirectory: true)
        }

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
    }
}

/// Shows plain-text app logs in a read-only window owned by Photos Wallpaper.
final class PlainTextLogWindow {
    private let title: String
    private var window: NSWindow?
    private weak var textView: NSTextView?

    init(title: String) {
        self.title = title
    }

    @MainActor
    func show(_ text: String) {
        if let window, window.isVisible, textView != nil {
            update(with: text)
            bringToFront(window)
            return
        }

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let textView = makeTextView(text: text, font: font)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        let window = NSWindow(contentViewController: NSViewController())
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentView = scrollView
        window.setContentSize(Self.windowSize(for: text, font: font))
        window.center()
        window.isReleasedWhenClosed = false
        bringToFront(window)

        self.textView = textView
        self.window = window
        scrollToBottomAfterLayout(textView)
    }

    @MainActor
    func update(with text: String) {
        guard let textView, window?.isVisible == true else { return }
        updateTextView(textView, with: text)
    }

    #if DEBUG
    @MainActor
    var displayedTextForTesting: String? {
        textView?.string
    }
    #endif

    private func makeTextView(text: String, font: NSFont) -> NSTextView {
        let textView = NSTextView()
        textView.string = text
        textView.font = font
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        return textView
    }

    @MainActor
    private func updateTextView(_ textView: NSTextView, with text: String) {
        let wasNearBottom = isScrolledNearBottom(textView)
        let previousFirstVisibleCharacterIndex = firstVisibleCharacterIndex(in: textView)

        if text.hasPrefix(textView.string) {
            let appendedText = String(text.dropFirst(textView.string.count))
            if !appendedText.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.textColor
                ]
                textView.textStorage?.append(NSAttributedString(string: appendedText, attributes: attributes))
            }
        } else {
            textView.string = text
        }

        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        if wasNearBottom {
            scrollToBottom(textView)
        } else if let previousFirstVisibleCharacterIndex {
            let characterIndex = min(previousFirstVisibleCharacterIndex, max(textView.string.count - 1, 0))
            textView.scrollRangeToVisible(NSRange(location: characterIndex, length: 0))
        }
    }

    @MainActor
    private func scrollToBottomAfterLayout(_ textView: NSTextView) {
        scrollToBottom(textView)
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            self.scrollToBottom(textView)
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                self.scrollToBottom(textView)
            }
        }
    }

    @MainActor
    private func scrollToBottom(_ textView: NSTextView) {
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        textView.scrollToEndOfDocument(nil)
        if let scrollView = textView.enclosingScrollView {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @MainActor
    private func isScrolledNearBottom(_ textView: NSTextView) -> Bool {
        let visibleRect = textView.visibleRect
        let distanceFromBottom = textView.bounds.maxY - visibleRect.maxY
        return distanceFromBottom < 40
    }

    @MainActor
    private func firstVisibleCharacterIndex(in textView: NSTextView) -> Int? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        guard glyphRange.location != NSNotFound else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphRange.location)
    }

    @MainActor
    private func bringToFront(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    @MainActor
    private static func windowSize(for text: String, font: NSFont) -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 800)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let longestLineWidth = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { NSString(string: String($0)).size(withAttributes: attributes).width }
            .max() ?? 0

        let desiredWidth = longestLineWidth + 80
        let width = min(max(desiredWidth, 760), visibleFrame.width - 80)
        let height = min(max(520, visibleFrame.height * 0.55), visibleFrame.height - 120)
        return NSSize(width: width, height: height)
    }
}

/// Appends a plain-text runtime log for diagnosing what the app did while running.
final class AppRuntimeLogger {
    static let shared = AppRuntimeLogger()

    private static let defaultMaxLogSizeBytes: UInt64 = 5 * 1024 * 1024
    private static let defaultRetainedLineCount = 100
    private static let sessionLogExplanation = "Runtime log. This file starts fresh each time Photos Wallpaper launches."

    private let logURL: URL
    private let logFile: BoundedLogFile
    private let dateFormatter: DateFormatter
    private let logWindow = PlainTextLogWindow(title: "Photos Wallpaper Runtime Log")
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.runtime-log")

    convenience init(fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        let directoryURL = AppLogStorage.directoryURL(fileManager: fileManager)
        let logURL = directoryURL.appendingPathComponent("runtime.log")
        self.init(logURL: logURL, fileManager: fileManager, maxLogSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)
    }

    init(logURL: URL, fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        self.logURL = logURL
        self.logFile = BoundedLogFile(logURL: logURL, fileManager: fileManager, maxSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss z"
        self.dateFormatter = formatter

        resetForCurrentSession()
    }

    func record(_ message: String, timestamp: Date = Date()) {
        writeQueue.async {
            self.write("[\(self.dateFormatter.string(from: timestamp))] \(message)\n")
            self.updateOpenRuntimeLogWindow()
        }
    }

    func openRuntimeLog() {
        do {
            let runtimeText = try writeQueue.sync {
                try logFile.ensureLogFileExists()
                return try String(contentsOf: logURL, encoding: .utf8)
            }
            DispatchQueue.main.async {
                self.logWindow.show(Self.displayText(for: runtimeText))
            }
        } catch {
            #if DEBUG
            print("AppRuntimeLogger: failed to open runtime log: \(error)")
            #endif
        }
    }

    #if DEBUG
    @MainActor
    var displayedRuntimeLogTextForTesting: String? {
        logWindow.displayedTextForTesting
    }
    #endif

    private func write(_ text: String) {
        do {
            try logFile.append(text)
        } catch {
            #if DEBUG
            print("AppRuntimeLogger: failed to write runtime log: \(error)")
            #endif
        }
    }

    private func resetForCurrentSession() {
        do {
            try logFile.reset()
        } catch {
            #if DEBUG
            print("AppRuntimeLogger: failed to reset runtime log: \(error)")
            #endif
        }
    }

    private func updateOpenRuntimeLogWindow() {
        guard let runtimeText = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.logWindow.update(with: Self.displayText(for: runtimeText))
        }
    }

    private static func displayText(for logText: String) -> String {
        sessionLogExplanation + "\n\n" + logText
    }
}

/// Appends a plain-text history file for wallpaper changes in the current app session.
final class WallpaperHistoryLogger: WallpaperHistoryLogging {
    private static let defaultMaxLogSizeBytes: UInt64 = 10 * 1024 * 1024
    private static let defaultRetainedLineCount = 100
    private static let sessionHistoryExplanation = "Wallpaper history. This list starts fresh each time Photos Wallpaper launches."

    private let logURL: URL
    private let logFile: BoundedLogFile
    private let currentWallpapersURL: URL
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private var currentWallpaperIdentifiersByScreen = [String: String]()
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.history-log")
    private let historyWindow = PlainTextLogWindow(title: "Photos Wallpaper History")

    convenience init(fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        let directoryURL = AppLogStorage.directoryURL(fileManager: fileManager)
        let logURL = directoryURL.appendingPathComponent("wallpaper-history.log")
        let currentWallpapersURL = directoryURL.appendingPathComponent("current-wallpapers.json")
        self.init(logURL: logURL,
                  currentWallpapersURL: currentWallpapersURL,
                  fileManager: fileManager,
                  maxLogSizeBytes: maxLogSizeBytes,
                  retainedLineCount: retainedLineCount)
    }

    init(logURL: URL,
         currentWallpapersURL: URL? = nil,
         fileManager: FileManager = .default,
         maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes,
         retainedLineCount: Int = defaultRetainedLineCount) {
        self.logURL = logURL
        self.logFile = BoundedLogFile(logURL: logURL, fileManager: fileManager, maxSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)
        self.currentWallpapersURL = currentWallpapersURL
            ?? logURL.deletingLastPathComponent().appendingPathComponent("current-wallpapers.json")
        self.fileManager = fileManager

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss"
        self.dateFormatter = formatter

        resetForCurrentSession()
        loadPersistedCurrentWallpapers()
    }

    func recordWallpaperChange(photoName: String, screenName: String, screenCount: Int, timestamp: Date) {
        let historyText = writeQueue.sync {
            writeWallpaperChange(photoName: photoName, screenName: screenName, screenCount: screenCount, timestamp: timestamp)
            rememberCurrentWallpaper(photoName: photoName, screenName: screenName, screenCount: screenCount)
            return try? String(contentsOf: logURL, encoding: .utf8)
        }

        if let historyText {
            DispatchQueue.main.async {
                self.updateOpenHistoryWindow(with: historyText)
            }
        }
    }

    func currentWallpaperIdentifiersSnapshot() -> [String] {
        writeQueue.sync {
            var seenIdentifiers = Set<String>()
            var identifiers: [String] = []
            for screenName in currentWallpaperIdentifiersByScreen.keys.sorted(by: screenSortOrder) {
                guard let identifier = currentWallpaperIdentifiersByScreen[screenName],
                      !seenIdentifiers.contains(identifier) else { continue }
                identifiers.append(identifier)
                seenIdentifiers.insert(identifier)
            }
            return identifiers
        }
    }

    private func rememberCurrentWallpaper(photoName: String, screenName: String, screenCount: Int) {
        guard let identifier = PhotoHistoryAssetDescriptionFormatter.localIdentifier(in: photoName) else {
            debugLog("WallpaperHistoryLogger: could not remember current wallpaper identifier for \(screenName).")
            return
        }

        currentWallpaperIdentifiersByScreen = currentWallpaperIdentifiersByScreen.filter { screenName, _ in
            guard let screenNumber = Self.screenNumber(in: screenName) else { return true }
            return screenNumber <= screenCount
        }
        currentWallpaperIdentifiersByScreen[screenName] = identifier
        persistCurrentWallpapers()
    }

    private func screenSortOrder(_ lhs: String, _ rhs: String) -> Bool {
        switch (Self.screenNumber(in: lhs), Self.screenNumber(in: rhs)) {
        case let (left?, right?):
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs < rhs
        }
    }

    private static func screenNumber(in screenName: String) -> Int? {
        screenName
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
            .first
    }

    private func writeWallpaperChange(photoName: String, screenName: String, screenCount: Int, timestamp: Date) {
        do {
            let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoName,
                                                           screenName: screenName,
                                                           screenCount: screenCount,
                                                           timestamp: timestamp,
                                                           dateFormatter: dateFormatter) + "\n"
            try logFile.append(line)
        } catch {
            debugLog("WallpaperHistoryLogger: failed to write history entry: \(error)")
        }
    }

    private func resetForCurrentSession() {
        do {
            try logFile.reset()
        } catch {
            debugLog("WallpaperHistoryLogger: failed to reset history log: \(error)")
        }
    }

    private func loadPersistedCurrentWallpapers() {
        do {
            guard fileManager.fileExists(atPath: currentWallpapersURL.path) else { return }
            let data = try Data(contentsOf: currentWallpapersURL)
            let persistedWallpapers = try JSONDecoder().decode([PersistedCurrentWallpaper].self, from: data)
            var identifiersByScreen = [String: String]()
            for wallpaper in persistedWallpapers {
                let screenName = wallpaper.screenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = wallpaper.localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !screenName.isEmpty, !identifier.isEmpty else { continue }
                identifiersByScreen[screenName] = identifier
            }
            currentWallpaperIdentifiersByScreen = identifiersByScreen
        } catch {
            debugLog("WallpaperHistoryLogger: failed to load current wallpaper identifiers: \(error)")
        }
    }

    private func persistCurrentWallpapers() {
        do {
            let directoryURL = currentWallpapersURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let wallpapers = currentWallpaperIdentifiersByScreen.keys
                .sorted(by: screenSortOrder)
                .compactMap { screenName -> PersistedCurrentWallpaper? in
                    guard let identifier = currentWallpaperIdentifiersByScreen[screenName] else { return nil }
                    return PersistedCurrentWallpaper(screenName: screenName, localIdentifier: identifier)
                }
            let data = try JSONEncoder().encode(wallpapers)
            try data.write(to: currentWallpapersURL, options: .atomic)
        } catch {
            debugLog("WallpaperHistoryLogger: failed to persist current wallpaper identifiers: \(error)")
        }
    }

    /// Ensures the history file exists and opens it in a read-only app window.
    func openHistoryLog() {
        do {
            let historyText = try writeQueue.sync {
                try logFile.ensureLogFileExists()
                return try String(contentsOf: logURL, encoding: .utf8)
            }
            historyWindow.show(Self.displayText(for: historyText))
        } catch {
            debugLog("WallpaperHistoryLogger: failed to open history log: \(error)")
        }
    }

    private func updateOpenHistoryWindow(with historyText: String) {
        historyWindow.update(with: Self.displayText(for: historyText))
    }

    #if DEBUG
    @MainActor
    var displayedHistoryTextForTesting: String? {
        historyWindow.displayedTextForTesting
    }
    #endif

    private static func displayText(for historyText: String) -> String {
        sessionHistoryExplanation + "\n\n" + historyText
    }
}

private struct PersistedCurrentWallpaper: Codable {
    let screenName: String
    let localIdentifier: String
}
