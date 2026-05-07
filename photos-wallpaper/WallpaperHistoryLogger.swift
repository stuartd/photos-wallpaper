import Foundation
import AppKit

protocol WallpaperHistoryLogging {
    func recordWallpaperChange(photoName: String, screenName: String, timestamp: Date)
    func openHistoryLog()
}

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
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
        formatter.timeStyle = .short
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
