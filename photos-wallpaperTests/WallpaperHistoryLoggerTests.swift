import Foundation
import AppKit
import Photos
import ServiceManagement
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func boundedLogFileCreatesMissingFileAndAppendsText() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logFile = BoundedLogFile(logURL: logURL, maxSizeBytes: 1_024, retainedLineCount: 10)

        try logFile.append("first\n")
        try logFile.append("second\n")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "first\nsecond\n")
    }

    @Test func boundedLogFileTrimsToRecentTailBeforeAppendingWhenSizeLimitWouldBeExceeded() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logFile = BoundedLogFile(logURL: logURL, maxSizeBytes: 15, retainedLineCount: 2)

        try logFile.append("one\n")
        try logFile.append("two\n")
        try logFile.append("three\n")
        try logFile.append("four\n")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "two\nthree\nfour\n")
    }

    @Test func runtimeLoggerClearsPreviousSessionLogOnStartup() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "yesterday\n".write(to: logURL, atomically: true, encoding: .utf8)

        _ = AppRuntimeLogger(logURL: logURL)

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "")
    }

    @Test func runtimeLoggerWritesHumanReadableLocalTimestamps() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = AppRuntimeLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss z"

        logger.record("hello", timestamp: timestamp)
        let didWriteLog = await waitForCondition {
            (try? String(contentsOf: logURL, encoding: .utf8)) == "[\(formatter.string(from: timestamp))] hello\n"
        }

        #expect(didWriteLog)
    }

    @Test func runtimeLoggerFormatsDiagnosticLogForAppWindow() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("runtime.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = AppRuntimeLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss z"

        logger.record("hello", timestamp: timestamp)
        let expectedLogText = "[\(formatter.string(from: timestamp))] hello\n"

        let didWriteLog = await waitForCondition {
            (try? String(contentsOf: logURL, encoding: .utf8)) == expectedLogText
        }

        #expect(didWriteLog)
        #expect(AppRuntimeLogger.displayText(for: expectedLogText) == "Runtime log. This file starts fresh each time Photos Wallpaper launches.\n\n\(expectedLogText)")
    }

    @Test func wallpaperHistoryLoggerClearsPreviousSessionLogOnStartup() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Photo ID OLD-ID/L0/001 was set as the wallpaper on 9 June 2026 at 13:16:18\n".write(to: logURL, atomically: true, encoding: .utf8)

        _ = WallpaperHistoryLogger(logURL: logURL)

        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text == "")
    }

    @Test func wallpaperHistoryLoggerFormatsSessionExplanationForAppWindow() async throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 1_717_974_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm:ss"

        logger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 1,
                                      timestamp: timestamp)
        let expectedHistoryText = "Photo ID FIRST-ID/L0/001 was set as the wallpaper on \(formatter.string(from: timestamp)) (IMG_0001.HEIC created 1 Jan 2024 at 12:00:00)\n"
        let historyText = try String(contentsOf: logURL, encoding: .utf8)

        #expect(historyText == expectedHistoryText)
        #expect(WallpaperHistoryLogger.displayText(for: historyText) == "Wallpaper history. This list starts fresh each time Photos Wallpaper launches.\n\n\(expectedHistoryText)")
    }

    @Test func wallpaperHistoryEntryFormatterBuildsExpectedMultipleScreenLine() {
        let photoDescription = PhotoHistoryAssetDescriptionFormatter.string(filename: "IMG_4501.JPG",
                                                                            creationDateText: "22 Dec 2015 at 11:58:17",
                                                                            localIdentifier: "A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001")

        let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoDescription,
                                                       screenName: "Screen 1",
                                                       screenCount: 2,
                                                       shownAtText: "10 June 2026 at 13:16:18")

        #expect(line == "Photo ID A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001 was set as the wallpaper for screen 1 on 10 June 2026 at 13:16:18 (IMG_4501.JPG created 22 Dec 2015 at 11:58:17)")
    }

    @Test func wallpaperHistoryEntryFormatterBuildsExpectedSingleScreenLine() {
        let photoDescription = PhotoHistoryAssetDescriptionFormatter.string(filename: "IMG_4501.JPG",
                                                                            creationDateText: "22 Dec 2015 at 11:58:17",
                                                                            localIdentifier: "A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001")

        let line = WallpaperHistoryEntryFormatter.line(photoDescription: photoDescription,
                                                       screenName: "Screen 1",
                                                       screenCount: 1,
                                                       shownAtText: "10 June 2026 at 13:16:18")

        #expect(line == "Photo ID A43B9DD7-D57E-4B0A-A748-D46A11F7A839/L0/001 was set as the wallpaper on 10 June 2026 at 13:16:18 (IMG_4501.JPG created 22 Dec 2015 at 11:58:17)")
    }

    @Test func photoHistoryAssetDescriptionFormatterIncludesFilenameCreationDateAndIdentifier() {
        let singleDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                          creationDateText: "1 May 2004 at 14:42:08",
                                                                          localIdentifier: "7")
        let twoDigitDay = PhotoHistoryAssetDescriptionFormatter.string(filename: "DSCN2550.jpg",
                                                                       creationDateText: "11 May 2004 at 14:42:08",
                                                                       localIdentifier: "7")

        #expect(singleDigitDay == "DSCN2550.jpg created 1 May 2004 at 14:42:08, id: 7")
        #expect(twoDigitDay == "DSCN2550.jpg created 11 May 2004 at 14:42:08, id: 7")
    }

    @Test func wallpaperHistoryLoggerSnapshotsCurrentWallpaperIdentifiersByScreen() {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let logger = WallpaperHistoryLogger(logURL: logURL)
        let timestamp = Date(timeIntervalSince1970: 0)

        logger.recordWallpaperChange(photoName: "IMG_0002.HEIC created 2 Jan 2024 at 12:00:00, id: SECOND-ID/L0/001",
                                      screenName: "Screen 2",
                                      screenCount: 2,
                                      timestamp: timestamp)
        logger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 2,
                                      timestamp: timestamp)
        logger.recordWallpaperChange(photoName: "IMG_DUPLICATE.HEIC created 3 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                      screenName: "Screen 3",
                                      screenCount: 3,
                                      timestamp: timestamp)

        #expect(logger.currentWallpaperIdentifiersSnapshot() == ["FIRST-ID/L0/001", "SECOND-ID/L0/001"])
        #expect(logger.currentWallpaperIdentifiersSnapshot(forScreenNumbers: [2]) == ["SECOND-ID/L0/001"])

        logger.recordWallpaperChange(photoName: "IMG_SINGLE.HEIC created 4 Jan 2024 at 12:00:00, id: SINGLE-ID/L0/001",
                                      screenName: "Screen 1",
                                      screenCount: 1,
                                      timestamp: timestamp)

        #expect(logger.currentWallpaperIdentifiersSnapshot() == ["SINGLE-ID/L0/001"])
    }

    @Test func wallpaperHistoryLoggerRestoresCurrentWallpaperIdentifiersFromPreviousSession() throws {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let timestamp = Date(timeIntervalSince1970: 0)

        let firstSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        firstSessionLogger.recordWallpaperChange(photoName: "IMG_0002.HEIC created 2 Jan 2024 at 12:00:00, id: SECOND-ID/L0/001",
                                                 screenName: "Screen 2",
                                                 screenCount: 2,
                                                 timestamp: timestamp)
        firstSessionLogger.recordWallpaperChange(photoName: "IMG_0001.HEIC created 1 Jan 2024 at 12:00:00, id: FIRST-ID/L0/001",
                                                 screenName: "Screen 1",
                                                 screenCount: 2,
                                                 timestamp: timestamp)

        let restoredLogger = WallpaperHistoryLogger(logURL: logURL)

        #expect(restoredLogger.currentWallpaperIdentifiersSnapshot() == ["FIRST-ID/L0/001", "SECOND-ID/L0/001"])
        #expect(restoredLogger.currentSessionWallpaperIdentifiersSnapshot().isEmpty)
        #expect(try String(contentsOf: logURL, encoding: .utf8) == "")
    }

    @Test func wallpaperHistoryLoggerSnapshotsOnlyWallpapersSetInTheCurrentSession() {
        let logURL = temporaryTestDirectory().appendingPathComponent("wallpaper-history.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        let timestamp = Date(timeIntervalSince1970: 0)

        let firstSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        firstSessionLogger.recordWallpaperChange(photoName: "IMG_OLD.HEIC created 1 Jan 2024 at 12:00:00, id: OLD-ID/L0/001",
                                                 screenName: "Screen 1",
                                                 screenCount: 1,
                                                 timestamp: timestamp)
        let currentSessionLogger = WallpaperHistoryLogger(logURL: logURL)
        currentSessionLogger.recordWallpaperChange(photoName: "IMG_NEW.HEIC created 2 Jan 2024 at 12:00:00, id: NEW-ID/L0/001",
                                                   screenName: "Screen 1",
                                                   screenCount: 1,
                                                   timestamp: timestamp)

        #expect(currentSessionLogger.currentWallpaperIdentifiersSnapshot() == ["NEW-ID/L0/001"])
        #expect(currentSessionLogger.currentSessionWallpaperIdentifiersSnapshot() == ["NEW-ID/L0/001"])
    }

}
