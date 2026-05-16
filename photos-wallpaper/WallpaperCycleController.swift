import Foundation
import SwiftUI
import AppKit
import Combine
import Photos
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

protocol WakeEventObservation: AnyObject {
    func invalidate()
}

protocol WakeEventObserving {
    func observeWake(_ handler: @escaping () -> Void) -> WakeEventObservation
}

final class NotificationWakeEventObservation: WakeEventObservation {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func invalidate() {
        if let token {
            center.removeObserver(token)
            self.token = nil
        }
    }
}

struct AppKitWakeEventObserver: WakeEventObserving {
    func observeWake(_ handler: @escaping () -> Void) -> WakeEventObservation {
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(forName: NSWorkspace.didWakeNotification,
                                       object: nil,
                                       queue: .main) { _ in
            handler()
        }
        return NotificationWakeEventObservation(center: center, token: token)
    }
}

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
    struct Option {
        let frequency: CycleFrequency
        let displayName: String
        let seconds: TimeInterval?
    }

    case onLogin
    case onWakeup
    #if DEBUG
    case oneSecond // debug only as intended to be used for stress tests, not as an actual option
    #endif
    case fiveSeconds
    case minute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hour
    case day

    static let allCases: [CycleFrequency] = options.map(\.frequency)

    static let options: [Option] = {
        var options = [
            Option(frequency: .onLogin, displayName: "On Login", seconds: nil),
            Option(frequency: .onWakeup, displayName: "On Wake", seconds: nil),
            Option(frequency: .fiveSeconds, displayName: "Every 5 seconds", seconds: 5),
            Option(frequency: .minute, displayName: "Every minute", seconds: 60),
            Option(frequency: .fiveMinutes, displayName: "Every 5 minutes", seconds: 5 * 60),
            Option(frequency: .fifteenMinutes, displayName: "Every 15 minutes", seconds: 15 * 60),
            Option(frequency: .thirtyMinutes, displayName: "Every 30 minutes", seconds: 30 * 60),
            Option(frequency: .hour, displayName: "Every hour", seconds: 60 * 60),
            Option(frequency: .day, displayName: "Every day", seconds: 60 * 60 * 24)
        ]
        #if DEBUG
        options.append(Option(frequency: .oneSecond, displayName: "Every second", seconds: 1))
        #endif
        return options
    }()

    /// Stable identifier for SwiftUI list/picker bindings.
    var id: String { rawValue }

    /// Timer interval used by the wallpaper cycle scheduler. Event-based modes do not have one.
    var seconds: TimeInterval? {
        option.seconds
    }

    /// User-facing label shown in the menu bar picker.
    var displayName: String {
        option.displayName
    }

    private var option: Option {
        guard let option = Self.options.first(where: { $0.frequency == self }) else {
            preconditionFailure("Missing cycle frequency option for \(self).")
        }
        return option
    }
}

/// Coordinates the wallpaper cycle.
///
/// Responsibilities:
/// - remember the user's chosen schedule
/// - install the right timer, login, or wake trigger
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
            // Rebuild the schedule trigger so the new frequency takes effect immediately.
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
    private let wakeEventObserver: WakeEventObserving
    private var wakeObservation: WakeEventObservation?
    private var hasNotifiedMissingPhotos = false
    private var isCycleInProgress = false
    private var pendingImageRequests = 0

    /// Production initializer used by the app.
    convenience init() {
        self.init(photoManager: PhotoManager.shared,
                  defaults: UserDefaults.standard,
                  historyLogger: WallpaperHistoryLogger(),
                  notifier: UserNotificationWallpaperCycleNotifier(),
                  screenProvider: AppKitScreenProvider(),
                  wakeEventObserver: AppKitWakeEventObserver(),
                  timerScheduler: FoundationTimerScheduler())
    }

    /// Injection-friendly initializer used by tests and by the convenience initializer above.
    init(photoManager: PhotoManaging,
         defaults: KeyValueStoring,
         historyLogger: WallpaperHistoryLogging,
         notifier: WallpaperCycleNotifying,
         screenProvider: ScreenProviding,
         wakeEventObserver: WakeEventObserving,
         timerScheduler: TimerScheduling) {
        self.photoManager = photoManager
        self.defaults = defaults
        self.historyLogger = historyLogger
        self.notifier = notifier
        self.screenProvider = screenProvider
        self.wakeEventObserver = wakeEventObserver
        self.timerScheduler = timerScheduler
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let f = CycleFrequency(rawValue: raw) {
            self.frequency = f
        } else {
            self.frequency = .hour
        }
        scheduleCycleTrigger()
    }

    /// Runs one wallpaper cycle immediately.
    ///
    /// This is used by the menu command and intentionally shares the same refresh pipeline as
    /// scheduled and wake-triggered cycles.
    func triggerNow() {
        debugLog("WallpaperCycleController: manual wallpaper refresh requested.")
        // `Task {}` starts an async unit of work while keeping the refresh on the main actor.
        Task { @MainActor in
            self.tick()
        }
    }

    /// Replaces any existing schedule trigger with one based on the current frequency.
    private func scheduleCycleTrigger() {
        timer?.invalidate()
        timer = nil
        wakeObservation?.invalidate()
        wakeObservation = nil

        switch frequency {
        case .onLogin:
            debugLog("WallpaperCycleController: scheduling one wallpaper cycle for login.")
            tick()
        case .onWakeup:
            debugLog("WallpaperCycleController: observing system wake notifications.")
            wakeObservation = wakeEventObserver.observeWake { [weak self] in
                Task { @MainActor [weak self] in
                    self?.tick()
                }
            }
        case .fiveSeconds, .minute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .hour, .day:
            scheduleTimerTrigger()
        #if DEBUG
        case .oneSecond:
            scheduleTimerTrigger()
        #endif
        }
    }

    private func scheduleTimerTrigger() {
        guard let seconds = frequency.seconds else { return }
        debugLog("WallpaperCycleController: scheduling timer for \(frequency.displayName) (\(seconds)s).")
        timer = timerScheduler.scheduledTimer(interval: seconds, repeats: true) { [weak self] in
            // `[weak self]` avoids the timer retaining the controller forever. Without that, the
            // controller and timer can keep each other alive even if the app wanted to release one.
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func rescheduleTimer() {
        scheduleCycleTrigger()
    }

    /// Executes one full wallpaper refresh across every connected display.
    ///
    /// The method stays on the main actor because it touches AppKit screen objects and because the
    /// surrounding UI state (`@Published frequency`, notification gating) is actor-isolated.
    private func tick() {
        guard !isCycleInProgress else {
            debugLog("WallpaperCycleController: skipping cycle because a previous cycle is still running.")
            return
        }
        isCycleInProgress = true
        debugLog("WallpaperCycleController: starting wallpaper cycle.")
        let screens = screenProvider.screens
        debugLog("WallpaperCycleController: found \(screens.count) screen(s).")
        guard !screens.isEmpty else {
            debugLog("WallpaperCycleController: aborting cycle because no screens were found.")
            finishCycle()
            return
        }
        let assets: [PHAsset]
        switch photoManager.getRandomPhotos(count: screens.count) {
        case .photos(let selectedAssets):
            assets = selectedAssets
        case .waitingForAuthorization:
            debugLog("WallpaperCycleController: waiting for Photos authorization before selecting wallpapers.")
            finishCycle()
            return
        case .unavailable:
            assets = []
        }
        debugLog("WallpaperCycleController: selected \(assets.count) photo asset(s) for \(screens.count) screen(s).")
        guard !assets.isEmpty else {
            if !hasNotifiedMissingPhotos {
                debugLog("WallpaperCycleController: no photo assets available, posting notification.")
                notifier.notifyNoPhotosAvailable()
                hasNotifiedMissingPhotos = true
            } else {
                debugLog("WallpaperCycleController: no photo assets available, notification already shown.")
            }
            finishCycle()
            return
        }
        hasNotifiedMissingPhotos = false

        // `zip` pairs screens with assets 1:1. The request itself is async, so each screen continues
        // independently after this loop starts the image fetches.
        let screenAssetPairs = Array(zip(screens, assets).enumerated())
        pendingImageRequests = screenAssetPairs.count
        for (index, pair) in screenAssetPairs {
            let (screen, asset) = pair
            let size = screen.pixelSize
            let screenName = "Monitor \(index + 1)"
            debugLog("WallpaperCycleController: requesting image \(index + 1) for screen size \(Int(size.width))x\(Int(size.height)).")
            // The completion closure is marked `@escaping` in the protocol, which means Photos may
            // call it later after this function has already returned.
            photoManager.requestImage(for: asset, targetSize: size) { [weak self, photoManager, historyLogger] image in
                defer {
                    Task { @MainActor [weak self] in
                        self?.completeImageRequest()
                    }
                }
                if let image = image {
                    debugLog("WallpaperCycleController: received image \(index + 1), applying wallpaper.")
                    if photoManager.setImageAsWallpaper(image, for: screen) {
                        // Move filename lookup off the main thread; no caching.
                        DispatchQueue.global(qos: .userInitiated).async {
                            let photoName = photoManager.displayName(for: asset)
                            historyLogger.recordWallpaperChange(photoName: photoName,
                                                                screenName: screenName,
                                                                timestamp: Date())
                        }
                    }
                } else {
                    debugLog("WallpaperCycleController: image request \(index + 1) returned nil.")
                }
            }
        }
    }

    private func completeImageRequest() {
        pendingImageRequests -= 1
        if pendingImageRequests <= 0 {
            finishCycle()
        }
    }

    private func finishCycle() {
        pendingImageRequests = 0
        isCycleInProgress = false
    }
}

private extension NSScreen {
    var pixelSize: CGSize {
        CGSize(width: frame.size.width * backingScaleFactor,
               height: frame.size.height * backingScaleFactor)
    }
}
