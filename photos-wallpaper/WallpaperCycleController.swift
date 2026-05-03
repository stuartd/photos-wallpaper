import Foundation
import SwiftUI
import AppKit
import Combine

protocol WallpaperCycleControlling: AnyObject, ObservableObject {
    var frequency: CycleFrequency { get set }
    func triggerNow()
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
    private let timerScheduler: TimerScheduling
    private var timer: CancellableTimer?

    /// Restores the saved frequency and starts the repeating timer that drives wallpaper shuffling for the app lifecycle.
    convenience init() {
        self.init(photoManager: PhotoManager.shared,
                  defaults: UserDefaults.standard,
                  timerScheduler: FoundationTimerScheduler())
    }

    init(photoManager: PhotoManaging,
         defaults: KeyValueStoring,
         timerScheduler: TimerScheduling) {
        self.photoManager = photoManager
        self.defaults = defaults
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
        // Stop early if the photo library fetch returned no available assets.
        guard let asset = photoManager.getRandomPhoto() else { return }
        // Use the main screen size as the requested target resolution, with a fallback for safety.
        let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        // Ask the photo manager to load an image for the selected asset at the desired size.
        photoManager.requestImage(for: asset, targetSize: size) { [photoManager] image in
            // Continue only when the Photos framework successfully produced an image.
            if let image = image {
                // Pass the rendered image to the photo manager so it can be written out and set as wallpaper.
                photoManager.setImageAsWallpaper(image)
            }
        }
    }
}
