import Foundation
import SwiftUI
import AppKit
import Combine
import UserNotifications

protocol WallpaperCycleControlling: AnyObject, ObservableObject {
    var frequency: CycleFrequency { get set }
    func triggerNow()
}

/// Small notification abstraction so tests can verify "no photos" behavior without touching
/// `UNUserNotificationCenter`.
protocol WallpaperCycleNotifying {
    func notifyNoPhotosAvailable()
}

/// Production notifier used when the photo library is empty.
///
/// Notifications are requested lazily here instead of up-front at launch so the app only asks for
/// permission if it actually needs to explain a missing-library situation.
final class UserNotificationWallpaperCycleNotifier: WallpaperCycleNotifying {
    private let center = UNUserNotificationCenter.current()

    func notifyNoPhotosAvailable() {
        Task {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = "No Photos Available"
            content.body = "Add photos to your library so the app can rotate wallpapers."
            content.sound = .default

            let request = UNNotificationRequest(identifier: "no-photos-available",
                                                content: content,
                                                trigger: nil)
            try? await center.add(request)
        }
    }
}

protocol ScreenProviding {
    var screens: [NSScreen] { get }
}

/// Thin wrapper around `NSScreen.screens` so tests can inject a fake monitor layout.
struct AppKitScreenProvider: ScreenProviding {
    var screens: [NSScreen] { NSScreen.screens }
}

protocol KeyValueStoring: AnyObject {
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}

protocol CancellableTimer: AnyObject {
    func invalidate()
}

extension Timer: CancellableTimer {}

protocol TimerScheduling {
    func scheduledTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> CancellableTimer
}

/// Production timer scheduler backed by Foundation's run-loop timer.
struct FoundationTimerScheduler: TimerScheduling {
    func scheduledTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> CancellableTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            block()
        }
    }
}

enum CycleFrequency: String, CaseIterable, Identifiable {
    case second
    case minute
    case hour
    case day

    /// Stable identifier for SwiftUI list/picker bindings.
    var id: String { rawValue }

    /// Timer interval used by the wallpaper cycle scheduler.
    var seconds: TimeInterval {
        switch self {
        case .second: return 1
        case .minute: return 60
        case .hour: return 60 * 60
        case .day: return 60 * 60 * 24
        }
    }

    /// User-facing label shown in the menu bar picker.
    var displayName: String {
        switch self {
        case .second: return "Every second"
        case .minute: return "Every minute"
        case .hour: return "Every hour"
        case .day: return "Every day"
        }
    }
}

/// Coordinates the wallpaper cycle.
///
/// Responsibilities:
/// - remember the user's chosen schedule
/// - run a repeating timer
/// - map screens to photo assets
/// - trigger notification/UI side effects when the library is empty
///
/// It deliberately does not know how Photos or wallpaper writing work internally; those details
/// live behind protocols so the controller can be unit tested.
///
/// Quick Swift glossary:
/// - `@MainActor`: this type should only be touched on the main thread/actor, which matters for
///   UI and AppKit objects.
/// - `@Published`: changes to this property notify SwiftUI observers automatically.
/// - `protocol`: an interface/contract, used here so tests can inject fakes instead of real system
///   dependencies.
@MainActor final class WallpaperCycleController: WallpaperCycleControlling {
    private static let defaultsKey = "cycleFrequency"

    @Published var frequency: CycleFrequency {
        didSet {
            // Persist the newly selected frequency so the next launch resumes the same schedule.
            defaults.set(frequency.rawValue, forKey: Self.defaultsKey)
            // Rebuild the timer so the new interval takes effect immediately.
            rescheduleTimer()
        }
    }

    private let photoManager: PhotoManaging
    private let defaults: KeyValueStoring
    private let historyLogger: WallpaperHistoryLogging
    private let notifier: WallpaperCycleNotifying
    private let screenProvider: ScreenProviding
    private let timerScheduler: TimerScheduling
    private var timer: CancellableTimer?
    private var hasNotifiedMissingPhotos = false

    /// Production initializer used by the app.
    convenience init() {
        self.init(photoManager: PhotoManager.shared,
                  defaults: UserDefaults.standard,
                  historyLogger: WallpaperHistoryLogger(),
                  notifier: UserNotificationWallpaperCycleNotifier(),
                  screenProvider: AppKitScreenProvider(),
                  timerScheduler: FoundationTimerScheduler())
    }

    /// Injection-friendly initializer used by tests and by the convenience initializer above.
    init(photoManager: PhotoManaging,
         defaults: KeyValueStoring,
         historyLogger: WallpaperHistoryLogging,
         notifier: WallpaperCycleNotifying,
         screenProvider: ScreenProviding,
         timerScheduler: TimerScheduling) {
        self.photoManager = photoManager
        self.defaults = defaults
        self.historyLogger = historyLogger
        self.notifier = notifier
        self.screenProvider = screenProvider
        self.timerScheduler = timerScheduler
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let f = CycleFrequency(rawValue: raw) {
            self.frequency = f
        } else {
            self.frequency = .hour
        }
        scheduleTimer()
    }

    /// Runs one wallpaper cycle immediately.
    ///
    /// This is used by the menu command and intentionally shares the exact same pipeline as the
    /// repeating timer.
    func triggerNow() {
        debugLog("WallpaperCycleController: manual wallpaper refresh requested.")
        // `Task {}` starts an async unit of work. Here it is mostly a clean way to hop back into
        // the controller's main-actor-isolated context before doing AppKit work.
        Task { @MainActor in
            self.tick()
        }
    }

    /// Replaces any existing timer with one based on the current frequency.
    private func scheduleTimer() {
        timer?.invalidate()
        debugLog("WallpaperCycleController: scheduling timer for \(frequency.displayName) (\(frequency.seconds)s).")
        timer = timerScheduler.scheduledTimer(interval: frequency.seconds, repeats: true) { [weak self] in
            // `[weak self]` avoids the timer retaining the controller forever. Without that, the
            // controller and timer can keep each other alive even if the app wanted to release one.
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func rescheduleTimer() {
        scheduleTimer()
    }

    /// Executes one full wallpaper refresh across every connected display.
    ///
    /// The method stays on the main actor because it touches AppKit screen objects and because the
    /// surrounding UI state (`@Published frequency`, notification gating) is actor-isolated.
    private func tick() {
        debugLog("WallpaperCycleController: starting wallpaper cycle.")
        let screens = screenProvider.screens
        debugLog("WallpaperCycleController: found \(screens.count) screen(s).")
        guard !screens.isEmpty else {
            debugLog("WallpaperCycleController: aborting cycle because no screens were found.")
            return
        }
        let assets = photoManager.getRandomPhotos(count: screens.count)
        debugLog("WallpaperCycleController: selected \(assets.count) photo asset(s) for \(screens.count) screen(s).")
        guard !assets.isEmpty else {
            if !hasNotifiedMissingPhotos {
                debugLog("WallpaperCycleController: no photo assets available, posting notification.")
                notifier.notifyNoPhotosAvailable()
                hasNotifiedMissingPhotos = true
            } else {
                debugLog("WallpaperCycleController: no photo assets available, notification already shown.")
            }
            return
        }
        hasNotifiedMissingPhotos = false

        // `zip` pairs screens with assets 1:1. The request itself is async, so each screen continues
        // independently after this loop starts the image fetches.
        for (index, pair) in zip(screens, assets).enumerated() {
            let (screen, asset) = pair
            let size = screen.frame.size
            let photoName = photoManager.displayName(for: asset)
            let screenName = "Monitor \(index + 1)"
            debugLog("WallpaperCycleController: requesting image \(index + 1) for screen size \(Int(size.width))x\(Int(size.height)).")
            // The completion closure is marked `@escaping` in the protocol, which means Photos may
            // call it later after this function has already returned.
            photoManager.requestImage(for: asset, targetSize: size) { [photoManager, historyLogger] image in
                if let image = image {
                    debugLog("WallpaperCycleController: received image \(index + 1), applying wallpaper.")
                    if photoManager.setImageAsWallpaper(image, for: screen) {
                        historyLogger.recordWallpaperChange(photoName: photoName,
                                                            screenName: screenName,
                                                            timestamp: Date())
                    }
                } else {
                    debugLog("WallpaperCycleController: image request \(index + 1) returned nil.")
                }
            }
        }
    }
}

