import Foundation
import AppKit
import Combine
import ServiceManagement

/// Manages the app's "Start at Login" registration and the menu state that reflects it.
///
/// Responsibilities:
/// - read the current login-item status from macOS
/// - register or unregister the app when the user toggles the menu item
/// - offer to enable Start at Login when the selected schedule needs the app running after sign-in
///
/// Quick macOS API glossary:
/// - `SMAppService.mainApp`: ServiceManagement's modern API for registering this app bundle as a
///   login item, without installing a separate helper app or LaunchAgent file.
/// - login item: an app macOS launches automatically after the user signs in.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false

    init() {
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
        } catch {
            showLoginItemError(error)
        }
        refreshStatus()
    }

    /// Offers Start at Login whenever the selected schedule needs the app running after sign-in.
    func promptToEnableIfUseful(for frequency: CycleFrequency) {
        refreshStatus()
        guard shouldSuggestLoginItem(for: frequency), !isEnabled else { return }

        let alert = NSAlert()
        alert.messageText = "Start Photos Wallpaper at login?"
        alert.informativeText = "Wallpaper rotation can only continue after a shutdown or restart if the app starts automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            setEnabled(true)
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
        case .onLogin, .onWakeup:
            return true
        case .fiveSeconds, .minute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .hour, .day:
            return false
        #if DEBUG
        case .oneSecond:
            return false
        #endif
        }
    }

    private func showLoginItemError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t change 'start at login' setting"
        alert.informativeText = "Photos Wallpaper could not update whether it starts automatically. You can manage this in System Settings > General > Login Items & Extensions.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
