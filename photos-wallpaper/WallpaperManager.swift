import Foundation
import AppKit
import CoreGraphics

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

    /// Converts wallpaper operation failures into readable messages for callers higher in the wallpaper-setting chain.
    public var errorDescription: String? {
        // Choose the appropriate user-facing description for the specific failure case.
        switch self {
        // Explain that no matching screen could be resolved for the requested display identifier.
        case .screenNotFound:
            return "Screen not found for the specified display."
        // Explain that the workspace wallpaper API failed and include the underlying error when present.
        case .setFailed(let underlying):
            return "Failed to set wallpaper" + (underlying != nil ? ": \(underlying!)" : ".")
        }
    }
}

public struct WallpaperOptions {
    public var scaling: NSImageScaling
    public var allowClipping: Bool
    public var fillColor: NSColor?

    /// Initializes wallpaper presentation options that are later translated into `NSWorkspace` desktop image settings.
    public init(scaling: NSImageScaling = .scaleProportionallyUpOrDown,
                allowClipping: Bool = true,
                fillColor: NSColor? = nil) {
        // Store the requested scaling mode for later conversion into workspace options.
        self.scaling = scaling
        // Store whether the workspace is allowed to clip the image while fitting it to the display.
        self.allowClipping = allowClipping
        // Store the optional background fill color used by some scaling modes.
        self.fillColor = fillColor
    }

    /// Converts the strongly typed option model into the dictionary format consumed by `NSWorkspace` wallpaper APIs.
    fileprivate func asWorkspaceOptions() -> [NSWorkspace.DesktopImageOptionKey: Any] {
        // Seed the options dictionary with the required scaling and clipping keys.
        var dict: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: scaling.rawValue,
            .allowClipping: allowClipping
        ]
        // Add the fill color only when one was supplied by the caller.
        if let color = fillColor { dict[.fillColor] = color }
        // Return the finished dictionary to the wallpaper-setting methods.
        return dict
    }
}

public final class WallpaperManager: WallpaperManaging {
    private let workspace = NSWorkspace.shared

    /// Creates a wallpaper manager that wraps `NSWorkspace` so the rest of the app can set wallpapers through one abstraction.
    public init() {}

    /// Resolves a display ID into an `NSScreen` and forwards the request into the screen-based wallpaper-setting chain.
    public func setWallpaper(for displayID: CGDirectDisplayID,
                             to fileURL: URL,
                             options: WallpaperOptions = WallpaperOptions()) throws {
        // Find the screen whose backing display identifier matches the caller's requested display.
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            // Fail with a specific error when no screen can be matched to the provided display ID.
            throw WallpaperError.screenNotFound
        }
        // Reuse the screen-based overload once the display ID has been resolved.
        try setWallpaper(for: screen, to: fileURL, options: options)
    }

    /// Applies a wallpaper file to one specific screen, which is the core operation shared by higher-level helpers.
    public func setWallpaper(for screen: NSScreen,
                             to fileURL: URL,
                             options: WallpaperOptions = WallpaperOptions()) throws {
        // Attempt to ask `NSWorkspace` to apply the image file to the requested screen.
        do {
            try workspace.setDesktopImageURL(fileURL,
                                             for: screen,
                                             options: options.asWorkspaceOptions())
        } catch {
            // Wrap lower-level failures in the app's wallpaper-specific error type for consistent handling upstream.
            throw WallpaperError.setFailed(underlying: error)
        }
    }

    /// Applies the same wallpaper file to every connected screen, collecting the first failure so callers can react.
    public func setWallpaperOnAllScreens(to fileURL: URL,
                                         options: WallpaperOptions = WallpaperOptions()) throws {
        // Track the first error encountered while still attempting every screen.
        var firstError: Error?
        // Iterate through all currently connected screens and try to update each one.
        for screen in NSScreen.screens {
            // Attempt to set the wallpaper for the current screen.
            do {
                try workspace.setDesktopImageURL(fileURL,
                                                 for: screen,
                                                 options: options.asWorkspaceOptions())
            } catch {
                // Preserve only the first failure while allowing later screens to continue processing.
                if firstError == nil { firstError = error }
            }
        }
        // Surface an aggregated failure after the loop if any screen update failed.
        if let err = firstError { throw WallpaperError.setFailed(underlying: err) }
    }
}

private extension NSScreen {
    /// Reads the Core Graphics display identifier for a screen so wallpaper requests can bridge between APIs.
    var displayID: CGDirectDisplayID {
        // Pull the display number from the screen's device description and cast it to the expected Core Graphics type.
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return 0 }
        // Return the resolved display identifier to the caller.
        return id
    }
}
