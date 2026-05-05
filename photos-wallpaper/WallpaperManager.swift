import Foundation
import AppKit
import CoreGraphics

/// Minimal abstraction over wallpaper writes so production code can use `NSWorkspace` and tests can
/// swap in a fake.
public protocol WallpaperManaging: AnyObject {
    func setWallpaper(for displayID: CGDirectDisplayID,
                      to fileURL: URL,
                      options: WallpaperOptions) throws
    func setWallpaper(for screen: NSScreen,
                      to fileURL: URL,
                      options: WallpaperOptions) throws
    func setWallpaperOnAllScreens(to fileURL: URL,
                                  options: WallpaperOptions) throws
}

public enum WallpaperError: Error, LocalizedError {
    case screenNotFound
    case setFailed(underlying: Error?)

    /// Human-readable error strings used when wallpaper updates fail.
    public var errorDescription: String? {
        switch self {
        case .screenNotFound:
            return "Screen not found for the specified display."
        case .setFailed(let underlying):
            return "Failed to set wallpaper" + (underlying != nil ? ": \(underlying!)" : ".")
        }
    }
}

/// Strongly typed wrapper around the otherwise dictionary-based AppKit wallpaper options.
public struct WallpaperOptions {
    public var scaling: NSImageScaling
    public var allowClipping: Bool
    public var fillColor: NSColor?

    public init(scaling: NSImageScaling = .scaleProportionallyUpOrDown,
                allowClipping: Bool = true,
                fillColor: NSColor? = nil) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor
    }

    /// Converts the strongly typed model above into the dictionary shape AppKit expects.
    fileprivate func asWorkspaceOptions() -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var dict: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: scaling.rawValue,
            .allowClipping: allowClipping
        ]
        if let color = fillColor { dict[.fillColor] = color }
        return dict
    }
}

/// Production implementation that delegates to `NSWorkspace`.
///
/// AppKit's wallpaper API is file-based and screen-based, so this type mostly translates between
/// app-friendly input and the exact forms `NSWorkspace` requires.
///
/// Quick macOS API glossary:
/// - `NSWorkspace`: AppKit's grab-bag of system integration APIs; wallpaper setting lives here.
/// - `CGDirectDisplayID`: Core Graphics' low-level display identifier.
public final class WallpaperManager: WallpaperManaging {
    private let workspace = NSWorkspace.shared

    public init() {}

    public func setWallpaper(for displayID: CGDirectDisplayID,
                             to fileURL: URL,
                             options: WallpaperOptions = WallpaperOptions()) throws {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            throw WallpaperError.screenNotFound
        }
        try setWallpaper(for: screen, to: fileURL, options: options)
    }

    /// Core wallpaper write for one screen.
    public func setWallpaper(for screen: NSScreen,
                             to fileURL: URL,
                             options: WallpaperOptions = WallpaperOptions()) throws {
        do {
            try workspace.setDesktopImageURL(fileURL,
                                             for: screen,
                                             options: options.asWorkspaceOptions())
        } catch {
            throw WallpaperError.setFailed(underlying: error)
        }
    }

    /// Best-effort helper that tries every screen and rethrows the first failure afterwards.
    public func setWallpaperOnAllScreens(to fileURL: URL,
                                         options: WallpaperOptions = WallpaperOptions()) throws {
        var firstError: Error?
        for screen in NSScreen.screens {
            do {
                try workspace.setDesktopImageURL(fileURL,
                                                 for: screen,
                                                 options: options.asWorkspaceOptions())
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let err = firstError { throw WallpaperError.setFailed(underlying: err) }
    }
}

private extension NSScreen {
    /// Exposes the Core Graphics display identifier hidden inside AppKit's screen description.
    var displayID: CGDirectDisplayID {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return 0 }
        return id
    }
}
