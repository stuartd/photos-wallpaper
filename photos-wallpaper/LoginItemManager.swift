import Foundation
import AppKit
import Combine
import ServiceManagement

protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

enum StartAtLoginPromptResponse {
    case enable
    case notNow
}

protocol StartAtLoginPromptPresenting {
    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse
    func showLoginItemError(_ error: Error)
}

struct AppKitStartAtLoginPromptPresenter: StartAtLoginPromptPresenting {
    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse {
        let alert = NSAlert()
        alert.messageText = "Start Photos Wallpaper at login?"
        alert.informativeText = "To keep this wallpaper schedule running after you restart or sign back in, Photos Wallpaper needs to start automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .enable : .notNow
    }

    func showLoginItemError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t change 'start at login' setting"
        alert.informativeText = "Photos Wallpaper could not update whether it starts automatically. You can manage this in System Settings > General > Login Items & Extensions.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}

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
    private static let dismissedPromptDefaultsKey = "dismissedStartAtLoginPrompt"

    @Published private(set) var isEnabled = false

    private let defaults: KeyValueStoring
    private let loginItemService: LoginItemServicing
    private let promptPresenter: StartAtLoginPromptPresenting

    init(defaults: KeyValueStoring = UserDefaults.standard,
         loginItemService: LoginItemServicing = SMAppService.mainApp,
         promptPresenter: StartAtLoginPromptPresenting? = nil) {
        self.defaults = defaults
        self.loginItemService = loginItemService
        self.promptPresenter = promptPresenter ?? AppKitStartAtLoginPromptPresenter()
        refreshStatus()
    }

    /// Re-reads macOS state so the menu stays accurate if the user changed Login Items in System
    /// Settings while the app was running.
    func refreshStatus() {
        isEnabled = loginItemService.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try enable()
                defaults.set(false, forKey: Self.dismissedPromptDefaultsKey)
            } else {
                try disable()
            }
        } catch {
            promptPresenter.showLoginItemError(error)
        }
        refreshStatus()
    }

    /// Offers Start at Login whenever the selected schedule needs the app running after sign-in.
    func promptToEnableStartAtLogin() {
        refreshStatus()
        guard !isEnabled else { return }
        guard !defaults.bool(forKey: Self.dismissedPromptDefaultsKey) else { return }

        switch promptPresenter.askToEnableStartAtLogin() {
        case .enable:
            setEnabled(true)
        case .notNow:
            defaults.set(true, forKey: Self.dismissedPromptDefaultsKey)
        }
    }

    private func enable() throws {
        guard loginItemService.status != .enabled else { return }
        // Registering the main app lets macOS launch this same bundle at login. This works best
        // from an installed, signed app rather than a transient Xcode DerivedData build.
        try loginItemService.register()
    }

    private func disable() throws {
        guard loginItemService.status == .enabled else { return }
        try loginItemService.unregister()
    }
}
