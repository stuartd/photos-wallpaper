import Foundation
import AppKit

protocol WallpaperHistoryLogging {
    func recordWallpaperChange(photoName: String, screenName: String, timestamp: Date)
    func openHistoryLog()
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

    private func trimIfNeeded(forAdditionalBytes additionalBytes: UInt64) throws {
        let currentSize = try currentLogSize()
        guard currentSize > 0, currentSize + additionalBytes > maxSizeBytes else { return }

        let retainedText = try retainedTailText()
        try retainedText.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func retainedTailText() throws -> String {
        guard retainedLineCount > 0 else { return "" }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
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

/// Appends a plain-text runtime log for diagnosing what the app did while running.
final class AppRuntimeLogger {
    static let shared = AppRuntimeLogger()

    private static let defaultMaxLogSizeBytes: UInt64 = 5 * 1024 * 1024
    private static let defaultRetainedLineCount = 100

    private let logURL: URL
    private let logFile: BoundedLogFile
    private let dateFormatter = ISO8601DateFormatter()
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.runtime-log")

    convenience init(fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let directoryURL = applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
        let logURL = directoryURL.appendingPathComponent("runtime.log")
        self.init(logURL: logURL, fileManager: fileManager, maxLogSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)
    }

    init(logURL: URL, fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        self.logURL = logURL
        self.logFile = BoundedLogFile(logURL: logURL, fileManager: fileManager, maxSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)
    }

    func record(_ message: String, timestamp: Date = Date()) {
        writeQueue.async {
            self.write("[\(self.dateFormatter.string(from: timestamp))] \(message)\n")
        }
    }

    func openRuntimeLog() {
        writeQueue.async {
            self.write("")
            DispatchQueue.main.async {
                NSWorkspace.shared.open(self.logURL)
            }
        }
    }

    private func write(_ text: String) {
        do {
            try logFile.append(text)
        } catch {
            #if DEBUG
            print("AppRuntimeLogger: failed to write runtime log: \(error)")
            #endif
        }
    }
}

/// Appends a plain-text history file so you can later answer "which photo was that wallpaper?"
final class WallpaperHistoryLogger: WallpaperHistoryLogging {
    private static let defaultMaxLogSizeBytes: UInt64 = 10 * 1024 * 1024
    private static let defaultRetainedLineCount = 100

    private let logURL: URL
    private let logFile: BoundedLogFile
    private let dateFormatter: DateFormatter
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.history-log")

    convenience init(fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let directoryURL = applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
        let logURL = directoryURL.appendingPathComponent("wallpaper-history.log")
        self.init(logURL: logURL, fileManager: fileManager, maxLogSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)
    }

    init(logURL: URL, fileManager: FileManager = .default, maxLogSizeBytes: UInt64 = defaultMaxLogSizeBytes, retainedLineCount: Int = defaultRetainedLineCount) {
        self.logURL = logURL
        self.logFile = BoundedLogFile(logURL: logURL, fileManager: fileManager, maxSizeBytes: maxLogSizeBytes, retainedLineCount: retainedLineCount)

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        self.dateFormatter = formatter
    }

    func recordWallpaperChange(photoName: String, screenName: String, timestamp: Date) {
        writeQueue.sync {
            writeWallpaperChange(photoName: photoName, screenName: screenName, timestamp: timestamp)
        }
    }

    private func writeWallpaperChange(photoName: String, screenName: String, timestamp: Date) {
        do {
            let line = "\(photoName) was shown on \(screenName) on \(dateFormatter.string(from: timestamp))\n"
            try logFile.append(line)
        } catch {
            debugLog("WallpaperHistoryLogger: failed to write history entry: \(error)")
        }
    }

    /// Ensures the history file exists and opens it in the user's default editor/viewer.
    func openHistoryLog() {
        do {
            try writeQueue.sync {
                try logFile.ensureLogFileExists()
            }
            NSWorkspace.shared.open(logURL)
        } catch {
            debugLog("WallpaperHistoryLogger: failed to open history log: \(error)")
        }
    }
}
