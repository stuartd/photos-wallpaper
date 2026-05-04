import Foundation
import SwiftUI
import AppKit
import Combine
import UserNotifications

private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

protocol WallpaperCycleControlling: AnyObject, ObservableObject {
    var frequency: CycleFrequency { get set }
    func triggerNow()
}

protocol WallpaperCycleNotifying {
    func notifyNoPhotosAvailable()
}

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

    /// Returns the raw string identifier SwiftUI uses to distinguish frequency values in collections and pickers.
    var id: String { rawValue }

    /// Converts the selected frequency into the timer interval used by `WallpaperCycleController.scheduleTimer()`.
    var seconds: TimeInterval {
        // Map each enum case to the number of seconds the repeating timer should wait between wallpaper updates.
        switch self {
        // Fire once per second.
        case .second: return 1
        // Fire once per minute.
        case .minute: return 60
        // Fire once per hour.
        case .hour: return 60 * 60
        // Fire once per day.
        case .day: return 60 * 60 * 24
        }
    }

    /// Provides the menu label shown in the app's cycle-frequency picker for each enum case.
    var displayName: String {
        // Translate each enum case into user-facing text for the menu bar UI.
        switch self {
        // Label for one-second updates.
        case .second: return "Every second"
        // Label for one-minute updates.
        case .minute: return "Every minute"
        // Label for one-hour updates.
        case .hour: return "Every hour"
        // Label for one-day updates.
        case .day: return "Every day"
        }
    }
}

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
    private let notifier: WallpaperCycleNotifying
    private let screenProvider: ScreenProviding
    private let timerScheduler: TimerScheduling
    private var timer: CancellableTimer?
    private var hasNotifiedMissingPhotos = false

    /// Restores the saved frequency and starts the repeating timer that drives wallpaper shuffling for the app lifecycle.
    convenience init() {
        self.init(photoManager: PhotoManager.shared,
                  defaults: UserDefaults.standard,
                  notifier: UserNotificationWallpaperCycleNotifier(),
                  screenProvider: AppKitScreenProvider(),
                  timerScheduler: FoundationTimerScheduler())
    }

    init(photoManager: PhotoManaging,
         defaults: KeyValueStoring,
         notifier: WallpaperCycleNotifying,
         screenProvider: ScreenProviding,
         timerScheduler: TimerScheduling) {
        self.photoManager = photoManager
        self.defaults = defaults
        self.notifier = notifier
        self.screenProvider = screenProvider
        self.timerScheduler = timerScheduler
        // Read the last saved frequency from user defaults and decode it back into an enum value.
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let f = CycleFrequency(rawValue: raw) {
            // Use the previously persisted frequency when available.
            self.frequency = f
        } else {
            // Fall back to an hourly schedule for first launch or invalid saved data.
            self.frequency = .hour
        }
        // Start the repeating timer so automatic wallpaper cycling begins immediately after initialization.
        scheduleTimer()
    }

    /// Kicks off an immediate wallpaper refresh from the menu bar without waiting for the next timer fire.
    func triggerNow() {
        debugLog("WallpaperCycleController: manual wallpaper refresh requested.")
        // Hop onto a main-actor task because the controller and AppKit interactions are main-thread-bound.
        Task { @MainActor in
            // Reuse the same update pipeline the timer uses so manual and automatic shuffles behave the same.
            self.tick()
        }
    }

    /// Builds the repeating timer that periodically calls `tick()` to advance the wallpaper rotation chain.
    private func scheduleTimer() {
        // Cancel any existing timer before creating a replacement to avoid overlapping schedules.
        timer?.invalidate()
        debugLog("WallpaperCycleController: scheduling timer for \(frequency.displayName) (\(frequency.seconds)s).")
        // Create a new repeating timer using the currently selected frequency interval.
        timer = timerScheduler.scheduledTimer(interval: frequency.seconds, repeats: true) { [weak self] in
            // Re-enter the main actor before touching controller state or AppKit-bound work.
            Task { @MainActor [weak self] in
                // Trigger the wallpaper update pipeline if the controller still exists.
                self?.tick()
            }
        }
    }

    /// Recreates the timer after the user changes frequency so the schedule chain stays in sync with preferences.
    private func rescheduleTimer() {
        // Delegate to the timer-construction helper to keep scheduling logic in one place.
        scheduleTimer()
    }

    /// Runs the wallpaper update pipeline by choosing a photo, requesting an image, and handing it off for wallpaper application.
    private func tick() {
        debugLog("WallpaperCycleController: starting wallpaper cycle.")
        // Resolve the current display list first so this cycle targets every connected monitor.
        let screens = screenProvider.screens
        debugLog("WallpaperCycleController: found \(screens.count) screen(s).")
        guard !screens.isEmpty else {
            debugLog("WallpaperCycleController: aborting cycle because no screens were found.")
            return
        }
        // Pick as many distinct photos as possible so each monitor receives its own image for this cycle.
        let assets = photoManager.getRandomPhotos(count: screens.count)
        debugLog("WallpaperCycleController: selected \(assets.count) photo asset(s) for \(screens.count) screen(s).")
        // Notify once when the library cannot provide any photos, then wait for a later successful cycle before notifying again.
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
        // Request and apply one image per screen using the screen's native pixel size as the target.
        for (index, pair) in zip(screens, assets).enumerated() {
            let (screen, asset) = pair
            let size = screen.frame.size
            debugLog("WallpaperCycleController: requesting image \(index + 1) for screen size \(Int(size.width))x\(Int(size.height)).")
            photoManager.requestImage(for: asset, targetSize: size) { [photoManager] image in
                // Continue only when the Photos framework successfully produced an image.
                if let image = image {
                    debugLog("WallpaperCycleController: received image \(index + 1), applying wallpaper.")
                    // Pass the rendered image to the photo manager so it can be written out and set as wallpaper.
                    photoManager.setImageAsWallpaper(image, for: screen)
                } else {
                    debugLog("WallpaperCycleController: image request \(index + 1) returned nil.")
                }
            }
        }
    }
}
