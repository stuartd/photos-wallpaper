import Foundation
import AppKit
import CoreGraphics

public enum WallpaperError: Error, LocalizedError {
    case screenNotFound
    case setFailed(underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case .screenNotFound:
            return "Screen not found for the specified display."
        case .setFailed(let underlying):
            return "Failed to set wallpaper" + (underlying != nil ? ": \(underlying!)" : ".")
        }
    }
}

public struct WallpaperOptions {
    public var scaling: NSImageScaling
    public var allowClipping: Bool
    public var fillColor: NSColor?

    public init(scaling: NSImageScaling = .scaleProportionallyUpOrDown,
                allowClipping: Bool = false,
                fillColor: NSColor? = nil) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor
    }

    fileprivate func asWorkspaceOptions() -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var dict: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: scaling.rawValue,
            .allowClipping: allowClipping
        ]
        if let color = fillColor { dict[.fillColor] = color }
        return dict
    }
}

public final class WallpaperManager {
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
    var displayID: CGDirectDisplayID {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return 0 }
        return id
    }
}
