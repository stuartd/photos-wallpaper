//
//  SingleInstanceLock.swift
//  photos-wallpaper
//

import AppKit
import Darwin
import Foundation

enum SingleInstanceLockAcquisition {
    case acquired(SingleInstanceLock)
    case alreadyLocked
    case failed(Error)
}

/// Holds an advisory process lock so only one Photos Wallpaper instance runs per user.
final class SingleInstanceLock {
    private static let defaultBundleIdentifier = "com.rosehillsolutions.photoswallpaper"

    let lockURL: URL
    private let descriptor: CInt
    private var isReleased = false

    private init(lockURL: URL, descriptor: CInt) {
        self.lockURL = lockURL
        self.descriptor = descriptor
    }

    static func acquire(lockURL: URL = defaultLockURL()) -> SingleInstanceLockAcquisition {
        do {
            try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            return .failed(error)
        }

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return .failed(posixError(errno))
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(descriptor)

            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                return .alreadyLocked
            }

            return .failed(posixError(lockError))
        }

        writeOwnerProcessIdentifier(to: descriptor)
        return .acquired(SingleInstanceLock(lockURL: lockURL, descriptor: descriptor))
    }

    static func defaultLockURL(fileManager: FileManager = .default,
                               bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL {
        let directoryURL: URL

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            directoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("photos-wallpaper-tests-\(getpid())", isDirectory: true)
                .appendingPathComponent("photos-wallpaper", isDirectory: true)
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
            directoryURL = applicationSupport.appendingPathComponent("photos-wallpaper", isDirectory: true)
        }

        let lockFilename = "\(bundleIdentifier ?? defaultBundleIdentifier).lock"
        return directoryURL.appendingPathComponent(lockFilename)
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    deinit {
        release()
    }

    private static func writeOwnerProcessIdentifier(to descriptor: CInt) {
        let processText = "\(ProcessInfo.processInfo.processIdentifier)\n"
        processText.withCString { processCString in
            ftruncate(descriptor, 0)
            pwrite(descriptor, processCString, strlen(processCString), 0)
        }
    }

    private static func posixError(_ code: CInt) -> Error {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}

@MainActor
struct ExistingAppInstanceActivator {
    func activateExistingInstance(bundleIdentifier: String? = Bundle.main.bundleIdentifier,
                                  currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        guard let bundleIdentifier else { return }

        let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }

        existingInstance?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
