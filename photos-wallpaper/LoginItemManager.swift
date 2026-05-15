import Foundation
import AppKit
import Combine
import ServiceManagement

/// Manages the app's "Start at Login" registration and the menu state that reflects it.
///
/// Responsibilities:
/// - read the current login-item status from macOS
/// - register or unregister the app when the user toggles the menu item
/// - offer a one-time prompt when the selected wallpaper schedule depends on app relaunch
///
/// Quick macOS API glossary:
/// - `SMAppService.mainApp`: ServiceManagement's modern API for registering this app bundle as a
///   login item, without installing a separate helper app or LaunchAgent file.
/// - login item: an app macOS launches automatically after the user signs in.
/// - `UserDefaults`: lightweight per-user storage, used here only to avoid repeatedly prompting.
@MainActor
final class LoginItemManager: ObservableObject {
    private static let promptDeclinedKey = "startAtLoginPromptDeclined"

    @Published private(set) var isEnabled = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshStatus()
    }

    /// Re-reads macOS state so the menu stays accurate if the user changed Login Items in System
    /// Settings while the app was running.
    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try enable()
            } else {
                try disable()
            }
            // A manual toggle is a clear fresh preference, so allow future schedule changes to
            // prompt again if the user later turns Start at Login off.
            defaults.set(false, forKey: Self.promptDeclinedKey)
        } catch {
            showLoginItemError(error)
        }
        refreshStatus()
    }

    /// Offers Start at Login only after the user chooses a timed schedule where a restart would otherwise  stop rotation.
    func promptToEnableIfUseful(for frequency: CycleFrequency) {
        refreshStatus()
        guard shouldSuggestLoginItem(for: frequency), !isEnabled else { return }
        guard !defaults.bool(forKey: Self.promptDeclinedKey) else { return }

        let alert = NSAlert()
        alert.messageText = "Start Photos Wallpaper at login?"
        alert.informativeText = "Wallpaper rotation can only continue after a shutdown or restart if the app starts automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            setEnabled(true)
        } else {
            defaults.set(true, forKey: Self.promptDeclinedKey)
        }
    }

    private func enable() throws {
        guard SMAppService.mainApp.status != .enabled else { return }
        // Registering the main app lets macOS launch this same bundle at login. This works best
        // from an installed, signed app rather than a transient Xcode DerivedData build.
        try SMAppService.mainApp.register()
    }

    private func disable() throws {
        guard SMAppService.mainApp.status == .enabled else { return }
        try SMAppService.mainApp.unregister()
    }

    private func shouldSuggestLoginItem(for frequency: CycleFrequency) -> Bool {
        switch frequency {
        case .onLogin:
            return true
        case .onWakeup:
            return false
        case .fiveSeconds, .minute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .hour, .day:
            return true
        #if DEBUG
        case .oneSecond:
            return true
        #endif
        }
    }

    private func showLoginItemError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not update Start at Login"
        alert.informativeText = "You can manage login items in System Settings > General > Login Items & Extensions."
        alert.runModal()
    }
}
