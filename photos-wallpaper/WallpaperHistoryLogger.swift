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

/// Appends a plain-text runtime log for diagnosing what the app did while running.
final class AppRuntimeLogger {
    static let shared = AppRuntimeLogger()

    private let logURL: URL
    private let fileManager: FileManager
    private let dateFormatter = ISO8601DateFormatter()
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.runtime-log")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let directoryURL = applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
        self.logURL = directoryURL.appendingPathComponent("runtime.log")
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
            try ensureLogFileExists()
            guard !text.isEmpty else { return }

            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            #if DEBUG
            print("AppRuntimeLogger: failed to write runtime log: \(error)")
            #endif
        }
    }

    private func ensureLogFileExists() throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

/// Appends a plain-text history file so you can later answer "which photo was that wallpaper?"
final class WallpaperHistoryLogger: WallpaperHistoryLogging {
    private let logURL: URL
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private let writeQueue = DispatchQueue(label: "photos-wallpaper.history-log")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let directoryURL = applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
        self.logURL = directoryURL.appendingPathComponent("wallpaper-history.log")

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
            try ensureLogFileExists()

            let line = "\(photoName) was shown on \(screenName) on \(dateFormatter.string(from: timestamp))\n"
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            debugLog("WallpaperHistoryLogger: failed to write history entry: \(error)")
        }
    }

    /// Ensures the history file exists and opens it in the user's default editor/viewer.
    func openHistoryLog() {
        do {
            try writeQueue.sync {
                try ensureLogFileExists()
            }
            NSWorkspace.shared.open(logURL)
        } catch {
            debugLog("WallpaperHistoryLogger: failed to open history log: \(error)")
        }
    }

    private func ensureLogFileExists() throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
