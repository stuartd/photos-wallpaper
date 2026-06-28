import Foundation
import SwiftUI
import AppKit
import Combine
import Photos
import SystemConfiguration
import UserNotifications

protocol WallpaperCycleControlling: AnyObject, ObservableObject {
    var frequency: CycleFrequency? { get set }
    func triggerNow()
}

/// Small user-facing warning abstraction so tests can verify unavailable-library behavior without
/// touching AppKit alerts or `UNUserNotificationCenter`.
protocol WallpaperCycleNotifying {
    func notifyNoPhotosAvailable()
    func notifyPhotoLibraryPermissionDenied()
}

/// Production warning presenter used when the app needs to explain why wallpaper selection failed.
///
/// Notifications are requested lazily here instead of up-front at launch so the app only asks for
/// permission if it actually needs to explain a missing-library situation.
final class UserNotificationWallpaperCycleNotifier: NSObject, WallpaperCycleNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        logNotificationSettings(context: "startup")
    }

    func notifyNoPhotosAvailable() {
        queueNotification(identifier: "no-photos-available-\(UUID().uuidString)",
                          title: "No Photos Available",
                          body: "Photos Wallpaper can't set your wallpaper because no photos are available.")
    }

    func notifyPhotoLibraryPermissionDenied() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Photos Access Needed"
            alert.informativeText = "Photos Wallpaper does not have permission to read your Photos library.\n\nEnable access in System Settings > Privacy & Security > Photos, then try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func queueNotification(identifier: String, title: String, body: String) {
        Task {
            do {
                await logNotificationSettings(context: "before requesting authorization for \(identifier)")
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    debugLog("UserNotificationWallpaperCycleNotifier: notification authorization was not granted.")
                    return
                }

                await logNotificationSettings(context: "after requesting authorization for \(identifier)")

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(identifier: identifier,
                                                    content: content,
                                                    trigger: nil)
                try await center.add(request)
                debugLog("UserNotificationWallpaperCycleNotifier: queued notification \(identifier).")
            } catch {
                debugLog("UserNotificationWallpaperCycleNotifier: failed to queue notification \(identifier): \(error).")
            }
        }
    }

    private func logNotificationSettings(context: String) {
        Task {
            await logNotificationSettings(context: context)
        }
    }

    private func logNotificationSettings(context: String) async {
        let settings = await center.notificationSettings()
        debugLog("UserNotificationWallpaperCycleNotifier: notification settings \(context): authorization=\(Self.description(for: settings.authorizationStatus)), alerts=\(Self.description(for: settings.alertSetting)), sounds=\(Self.description(for: settings.soundSetting)).")
    }

    private static func description(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private static func description(for setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown(\(setting.rawValue))"
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        debugLog("UserNotificationWallpaperCycleNotifier: presenting foreground notification \(notification.request.identifier).")
        completionHandler([.banner, .list, .sound])
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
    func bool(forKey defaultName: String) -> Bool
    func integer(forKey defaultName: String) -> Int
    func double(forKey defaultName: String) -> Double
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

protocol ActiveUserSessionEventObservation: AnyObject {
    func invalidate()
}

protocol ActiveUserSessionEventObserving {
    func observeSessionDidBecomeActive(_ handler: @escaping () -> Void) -> ActiveUserSessionEventObservation
}

@MainActor protocol ScreenSleepStateProviding: AnyObject {
    var screensAreAsleep: Bool { get }
}

@MainActor protocol ActiveUserSessionProviding: AnyObject {
    var appOwnsActiveConsoleSession: Bool { get }
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

final class NotificationActiveUserSessionEventObservation: ActiveUserSessionEventObservation {
    private var invalidations: [() -> Void]

    init(invalidations: [() -> Void]) {
        self.invalidations = invalidations
    }

    func invalidate() {
        invalidations.forEach { $0() }
        invalidations = []
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

struct AppKitActiveUserSessionEventObserver: ActiveUserSessionEventObserving {
    func observeSessionDidBecomeActive(_ handler: @escaping () -> Void) -> ActiveUserSessionEventObservation {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceToken = workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                                         object: nil,
                                                         queue: .main) { _ in
            handler()
        }
        let distributedCenter = DistributedNotificationCenter.default()
        let unlockToken = distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                        object: nil,
                                                        queue: .main) { _ in
            handler()
        }
        return NotificationActiveUserSessionEventObservation(invalidations: [
            { workspaceCenter.removeObserver(workspaceToken) },
            { distributedCenter.removeObserver(unlockToken) }
        ])
    }
}

@MainActor final class AppKitScreenSleepStateProvider: ScreenSleepStateProviding {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private(set) var screensAreAsleep = false

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
        observe(NSWorkspace.screensDidSleepNotification, screensAreAsleep: true)
        observe(NSWorkspace.screensDidWakeNotification, screensAreAsleep: false)
        observe(NSWorkspace.willSleepNotification, screensAreAsleep: true)
        observe(NSWorkspace.didWakeNotification, screensAreAsleep: false)
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }

    private func observe(_ name: NSNotification.Name, screensAreAsleep: Bool) {
        let token = center.addObserver(forName: name,
                                       object: nil,
                                       queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screensAreAsleep = screensAreAsleep
                debugLog("AppKitScreenSleepStateProvider: screens are \(screensAreAsleep ? "asleep" : "awake").")
            }
        }
        tokens.append(token)
    }
}

@MainActor final class SystemActiveUserSessionProvider: ActiveUserSessionProviding {
    var appOwnsActiveConsoleSession: Bool {
        var consoleUID = uid_t.max
        var consoleGID = gid_t.max
        guard let consoleUser = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, &consoleGID) as String?,
              consoleUser != "loginwindow",
              consoleUID == getuid() else {
            return false
        }
        return true
    }
}

@MainActor final class AlwaysActiveUserSessionProvider: ActiveUserSessionProviding {
    var appOwnsActiveConsoleSession: Bool { true }
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

    // This covers three cases - actual login in, wake from sleep, and fast user switching - #21
    case onLogin
    #if DEBUG
    case oneSecond // debug only as intended to be used for stress tests, not as an actual option
    #endif
    case minute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hour
    case day

    static let allCases: [CycleFrequency] = options.map(\.frequency)

    static let options: [Option] = {
        var options = [
            Option(frequency: .onLogin, displayName: "When I log in", seconds: nil),
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
/// - trigger notification/UI side effects when photos are unavailable
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
    private static let nextScheduledCycleDueAtDefaultsKey = "nextScheduledCycleDueAt"
    private static let legacyDefaultsFilename = "com.rosehillsolutions.photoswallpaper.plist"
    private static let wakeCatchUpDelay: TimeInterval = 5 * 60
    private static let wakeCatchUpReadinessRetryDelay: TimeInterval = 10

    @Published var frequency: CycleFrequency? {
        didSet {
            guard hasLoadedInitialFrequency else { return }
            // Persist the newly selected frequency so the next launch resumes the same schedule.
            defaults.set(frequency?.rawValue, forKey: Self.defaultsKey)
            if frequency != oldValue {
                clearStoredScheduledCycleDueAt()
            }
            // Rebuild the schedule trigger so the new frequency takes effect immediately.
            scheduleCycleTrigger()
        }
    }
    @Published private(set) var isWaitingForPhotoAuthorization = false

    private let photoManager: PhotoManaging
    private let defaults: KeyValueStoring
    private let historyLogger: WallpaperHistoryLogging
    private let notifier: WallpaperCycleNotifying
    private let screenProvider: ScreenProviding
    private let timerScheduler: TimerScheduling
    private var timer: CancellableTimer?
    private var wakeCatchUpTimer: CancellableTimer?
    private let wakeEventObserver: WakeEventObserving
    private var wakeObservation: WakeEventObservation?
    private let activeUserSessionEventObserver: ActiveUserSessionEventObserving
    private var activeUserSessionObservation: ActiveUserSessionEventObservation?
    private let screenSleepStateProvider: ScreenSleepStateProviding
    private let activeUserSessionProvider: ActiveUserSessionProviding
    private let preflightsPhotoAccessWhenScheduling: Bool
    private let startsScheduleAutomatically: Bool
    private var lastAutomaticUnavailablePhotosReason: UnavailablePhotosReason?
    private var isCycleInProgress = false
    private var pendingImageRequests = 0
    private var hasLoadedInitialFrequency = false
    private var pendingAuthorizationRetryTrigger: WallpaperCycleTrigger?
    private var nextScheduledCycleDueAt: Date?
    private var hasLoggedDeferredScheduledCycle = false
    private var wakeGraceEndsAt: Date?
    private var isConfiguringInitialSchedule = true

    /// Production initializer used by the app.
    convenience init() {
        self.init(historyLogger: WallpaperHistoryLogger())
    }

    convenience init(historyLogger: WallpaperHistoryLogging) {
        self.init(photoManager: PhotoManager.shared,
                  defaults: UserDefaults.standard,
                  historyLogger: historyLogger,
                  notifier: UserNotificationWallpaperCycleNotifier(),
                  screenProvider: AppKitScreenProvider(),
                  wakeEventObserver: AppKitWakeEventObserver(),
                  activeUserSessionEventObserver: AppKitActiveUserSessionEventObserver(),
                  timerScheduler: FoundationTimerScheduler(),
                  screenSleepStateProvider: AppKitScreenSleepStateProvider(),
                  activeUserSessionProvider: SystemActiveUserSessionProvider(),
                  legacyDefaultsURL: Self.defaultLegacyDefaultsURL,
                  preflightsPhotoAccessWhenScheduling: !Self.isRunningUnitTests,
                  startsScheduleAutomatically: !Self.isRunningUnitTests)
    }

    /// Injection-friendly initializer used by tests and by the convenience initializer above.
    convenience init(photoManager: PhotoManaging,
                     defaults: KeyValueStoring,
                     historyLogger: WallpaperHistoryLogging,
                     notifier: WallpaperCycleNotifying,
                     screenProvider: ScreenProviding,
                     wakeEventObserver: WakeEventObserving,
                     activeUserSessionEventObserver: ActiveUserSessionEventObserving? = nil,
                     timerScheduler: TimerScheduling,
                     legacyDefaultsURL: URL? = nil) {
        self.init(photoManager: photoManager,
                  defaults: defaults,
                  historyLogger: historyLogger,
                  notifier: notifier,
                  screenProvider: screenProvider,
                  wakeEventObserver: wakeEventObserver,
                  activeUserSessionEventObserver: activeUserSessionEventObserver,
                  timerScheduler: timerScheduler,
                  screenSleepStateProvider: AppKitScreenSleepStateProvider(),
                  activeUserSessionProvider: AlwaysActiveUserSessionProvider(),
                  legacyDefaultsURL: legacyDefaultsURL,
                  preflightsPhotoAccessWhenScheduling: true)
    }

    init(photoManager: PhotoManaging,
         defaults: KeyValueStoring,
         historyLogger: WallpaperHistoryLogging,
         notifier: WallpaperCycleNotifying,
         screenProvider: ScreenProviding,
         wakeEventObserver: WakeEventObserving,
         activeUserSessionEventObserver: ActiveUserSessionEventObserving? = nil,
         timerScheduler: TimerScheduling,
         screenSleepStateProvider: ScreenSleepStateProviding,
         activeUserSessionProvider: ActiveUserSessionProviding,
         legacyDefaultsURL: URL? = nil,
         preflightsPhotoAccessWhenScheduling: Bool = true,
         startsScheduleAutomatically: Bool = true) {
        self.photoManager = photoManager
        self.defaults = defaults
        self.historyLogger = historyLogger
        self.notifier = notifier
        self.screenProvider = screenProvider
        self.wakeEventObserver = wakeEventObserver
        self.activeUserSessionEventObserver = activeUserSessionEventObserver ?? AppKitActiveUserSessionEventObserver()
        self.timerScheduler = timerScheduler
        self.screenSleepStateProvider = screenSleepStateProvider
        self.activeUserSessionProvider = activeUserSessionProvider
        self.preflightsPhotoAccessWhenScheduling = preflightsPhotoAccessWhenScheduling
        self.startsScheduleAutomatically = startsScheduleAutomatically
        if let raw = Self.storedFrequencyRawValue(defaults: defaults, legacyDefaultsURL: legacyDefaultsURL),
           let f = CycleFrequency(rawValue: raw) {
            self.frequency = f
        } else {
            self.frequency = nil
        }
        photoManager.photoAuthorizationDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.isWaitingForPhotoAuthorization = false
                self?.retryPendingAuthorizationCycleIfNeeded()
            }
        }
        hasLoadedInitialFrequency = true
        if startsScheduleAutomatically {
            scheduleCycleTrigger()
        }
        isConfiguringInitialSchedule = false
    }

    private static var defaultLegacyDefaultsURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent(legacyDefaultsFilename)
    }

    // Not ideal, but this will allow the permission tests to run without generating an actual request popup
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil
    }

    private static func storedFrequencyRawValue(defaults: KeyValueStoring, legacyDefaultsURL: URL?) -> String? {
        if let raw = defaults.string(forKey: defaultsKey) {
            return raw
        }

        guard let legacyRaw = legacyFrequencyRawValue(from: legacyDefaultsURL),
              CycleFrequency(rawValue: legacyRaw) != nil else {
            return nil
        }
        defaults.set(legacyRaw, forKey: defaultsKey)
        debugLog("WallpaperCycleController: migrated wallpaper schedule from legacy preferences.")
        return legacyRaw
    }

    private static func legacyFrequencyRawValue(from url: URL?) -> String? {
        guard let url,
              let legacyDefaults = NSDictionary(contentsOf: url),
              let raw = legacyDefaults[defaultsKey] as? String else {
            return nil
        }
        return raw
    }

    /// Runs one wallpaper cycle immediately.
    ///
    /// This is used by the menu command and intentionally shares the same refresh pipeline as
    /// scheduled and wake-triggered cycles.
    func triggerNow() {
        debugLog("WallpaperCycleController: manual wallpaper refresh requested.")
        // `Task {}` starts an async unit of work while keeping the refresh on the main actor.
        Task { @MainActor in
            self.tick(trigger: .manual)
        }
    }

    /// Replaces any existing schedule trigger with one based on the current frequency.
    private func scheduleCycleTrigger() {
        timer?.invalidate()
        timer = nil
        wakeCatchUpTimer?.invalidate()
        wakeCatchUpTimer = nil
        wakeGraceEndsAt = nil
        wakeObservation?.invalidate()
        wakeObservation = nil
        activeUserSessionObservation?.invalidate()
        activeUserSessionObservation = nil

        guard let frequency else {
            clearStoredScheduledCycleDueAt()
            debugLog("WallpaperCycleController: no wallpaper schedule selected.")
            return
        }
        if preflightsPhotoAccessWhenScheduling {
            switch photoManager.requestPhotoAccessIfNeeded() {
            case .ready:
                isWaitingForPhotoAuthorization = false
            case .waitingForAuthorization:
                isWaitingForPhotoAuthorization = true
            case .permissionDenied:
                isWaitingForPhotoAuthorization = false
                debugLog("WallpaperCycleController: Photos permission denied while configuring schedule.")
                notifier.notifyPhotoLibraryPermissionDenied()
            case .unavailable:
                isWaitingForPhotoAuthorization = false
                debugLog("WallpaperCycleController: Photos authorization unavailable while configuring schedule.")
            }
        }

        switch frequency {
        case .onLogin:
            clearStoredScheduledCycleDueAt()
            logScheduledWallpaperChanges(for: frequency)
            activeUserSessionObservation = activeUserSessionEventObserver.observeSessionDidBecomeActive { [weak self] in
                Task { @MainActor [weak self] in
                    self?.tick(trigger: .unlock)
                }
            }
            wakeObservation = wakeEventObserver.observeWake { [weak self] in
                Task { @MainActor [weak self] in
                    self?.tick(trigger: .wake)
                }
            }
        case .minute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .hour, .day:
            ensureStoredScheduledCycleDueAt(for: frequency)
            observeWakeForDeferredScheduledCycle()
            observeSessionActivationForDeferredScheduledCycle()
            scheduleTimerTrigger(for: frequency)
            if isConfiguringInitialSchedule {
                deferOverdueScheduledCycleAfterLaunchIfNeeded(for: frequency)
            } else {
                runDeferredScheduledCycleIfNeeded()
            }
            
        #if DEBUG
        case .oneSecond:
            ensureStoredScheduledCycleDueAt(for: frequency)
            observeWakeForDeferredScheduledCycle()
            observeSessionActivationForDeferredScheduledCycle()
            scheduleTimerTrigger(for: frequency)
            if isConfiguringInitialSchedule {
                deferOverdueScheduledCycleAfterLaunchIfNeeded(for: frequency)
            } else {
                runDeferredScheduledCycleIfNeeded()
            }
        #endif
        }
    }

    private func observeWakeForDeferredScheduledCycle() {
        wakeObservation = wakeEventObserver.observeWake { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDeferredScheduledCycleAfterWakeIfNeeded()
            }
        }
    }

    private func observeSessionActivationForDeferredScheduledCycle() {
        activeUserSessionObservation = activeUserSessionEventObserver.observeSessionDidBecomeActive { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDeferredScheduledCycleAfterSessionActivationIfNeeded()
            }
        }
    }

    private func ensureStoredScheduledCycleDueAt(for frequency: CycleFrequency) {
        guard let seconds = frequency.seconds else {
            clearStoredScheduledCycleDueAt()
            return
        }

        let storedTimestamp = defaults.double(forKey: Self.nextScheduledCycleDueAtDefaultsKey)
        if storedTimestamp > 0 {
            nextScheduledCycleDueAt = Date(timeIntervalSince1970: storedTimestamp)
        } else {
            storeNextScheduledCycleDueAt(Date().addingTimeInterval(seconds))
        }
    }

    private func storeNextScheduledCycleDueAt(_ date: Date) {
        nextScheduledCycleDueAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Self.nextScheduledCycleDueAtDefaultsKey)
    }

    private func clearStoredScheduledCycleDueAt() {
        nextScheduledCycleDueAt = nil
        hasLoggedDeferredScheduledCycle = false
        defaults.set(nil, forKey: Self.nextScheduledCycleDueAtDefaultsKey)
    }

    private func deferOverdueScheduledCycleAfterLaunchIfNeeded(for frequency: CycleFrequency) {
        guard let dueAt = nextScheduledCycleDueAt,
              Date() >= dueAt,
              let seconds = frequency.seconds else {
            return
        }
        hasLoggedDeferredScheduledCycle = false
        storeNextScheduledCycleDueAt(Date().addingTimeInterval(seconds))
        debugLog("WallpaperCycleController: deferred overdue scheduled cycle after app launch; next cycle follows the selected schedule.")
    }

    private func logScheduledWallpaperChanges(for frequency: CycleFrequency) {
        debugLog("WallpaperCycleController: scheduling wallpaper changes for '\(frequency.displayName)'.")
    }

    private func scheduleTimerTrigger(for frequency: CycleFrequency) {
        guard let seconds = frequency.seconds else { return }
        debugLog("WallpaperCycleController: scheduling wallpaper changes for '\(frequency.displayName)' (\(Int(seconds)) seconds).")
        timer = timerScheduler.scheduledTimer(interval: seconds, repeats: true) { [weak self] in
            // `[weak self]` avoids the timer retaining the controller forever. Without that, the
            // controller and timer can keep each other alive even if the app wanted to release one.
            Task { @MainActor [weak self] in
                self?.tick(trigger: .scheduled)
            }
        }
    }

    private enum WallpaperCycleTrigger {
        case manual
        case unlock
        case wake
        case scheduled

        var shouldAlwaysNotifyUnavailablePhotos: Bool {
            self == .manual
        }

        var requiresActiveUserSession: Bool {
            self != .manual
        }

        var logDescription: String {
            switch self {
            case .manual: return "manual trigger"
            case .unlock: return "unlock trigger"
            case .wake: return "wake trigger"
            case .scheduled: return "scheduled trigger"
            }
        }
    }

    /// Executes one full wallpaper refresh across every connected display.
    ///
    /// The method stays on the main actor because it touches AppKit screen objects and because the
    /// surrounding UI state (`@Published frequency`, notification gating) is actor-isolated.
    private func tick(trigger: WallpaperCycleTrigger) {
        if trigger.requiresActiveUserSession && !activeUserSessionProvider.appOwnsActiveConsoleSession {
            if deferScheduledCycleIfNeeded(trigger: trigger) {
                debugLog("WallpaperCycleController: skipping automatic cycle \(trigger.logDescription) because this app's user session is not the active console session.")
            } else if trigger != .scheduled {
                debugLog("WallpaperCycleController: skipping automatic cycle \(trigger.logDescription) because this app's user session is not the active console session.")
            }
            return
        }
        if trigger == .scheduled && screenSleepStateProvider.screensAreAsleep {
            if deferScheduledCycleIfNeeded(trigger: trigger) {
                debugLog("WallpaperCycleController: skipping scheduled cycle because the screens are asleep.")
            }
            return
        }
        if shouldDelayScheduledCycleForWakeGrace(trigger: trigger) {
            scheduleWakeCatchUpTimer()
            return
        }
        guard !isCycleInProgress else {
            debugLog("WallpaperCycleController: skipping cycle because a previous cycle is still running.")
            return
        }
        clearDeferredScheduledCycleIfNeeded(trigger: trigger)
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
            isWaitingForPhotoAuthorization = false
            if selectedAssets.isEmpty {
                notifyUnavailablePhotos(reason: .noPhotosAvailable, trigger: trigger)
                finishCycle()
                return
            }
            assets = selectedAssets
        case .waitingForAuthorization:
            isWaitingForPhotoAuthorization = true
            debugLog("WallpaperCycleController: waiting for Photos authorization before selecting wallpapers.")
            pendingAuthorizationRetryTrigger = trigger
            finishCycle()
            return
        case .permissionDenied:
            isWaitingForPhotoAuthorization = false
            notifyUnavailablePhotos(reason: .permissionDenied, trigger: trigger)
            finishCycle()
            return
        case .unavailable:
            isWaitingForPhotoAuthorization = false
            notifyUnavailablePhotos(reason: .noPhotosAvailable, trigger: trigger)
            finishCycle()
            return
        }

        debugLog("WallpaperCycleController: selected \(assets.count) photo asset(s) for \(screens.count) screen(s).")
        lastAutomaticUnavailablePhotosReason = nil

        // `zip` pairs screens with assets 1:1. The request itself is async, so each screen continues
        // independently after this loop starts the image fetches.
        let screenAssetPairs = Array(zip(screens, assets).enumerated())
        let screenCount = screenAssetPairs.count
        pendingImageRequests = screenAssetPairs.count
        for (index, pair) in screenAssetPairs {
            let (screen, asset) = pair
            let size = screen.pixelSize
            let screenName = "Screen \(index + 1)"
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
                        Task { @MainActor [weak self] in
                            self?.clearDeferredScheduledCycleAfterManualChangeIfNeeded(trigger: trigger)
                        }
                        // Move filename lookup off the main thread; no caching.
                        DispatchQueue.global(qos: .userInitiated).async {
                            let photoName = photoManager.displayName(for: asset)
                            historyLogger.recordWallpaperChange(photoName: photoName,
                                                                screenName: screenName,
                                                                screenCount: screenCount,
                                                                timestamp: Date())
                        }
                    }
                } else {
                    debugLog("WallpaperCycleController: image request \(index + 1) returned nil.")
                }
            }
        }
    }

    private func clearDeferredScheduledCycleAfterManualChangeIfNeeded(trigger: WallpaperCycleTrigger) {
        guard trigger == .manual,
              let seconds = frequency?.seconds else {
            return
        }
        wakeCatchUpTimer?.invalidate()
        wakeCatchUpTimer = nil
        wakeGraceEndsAt = nil
        hasLoggedDeferredScheduledCycle = false
        storeNextScheduledCycleDueAt(Date().addingTimeInterval(seconds))
        debugLog("WallpaperCycleController: cancelled deferred scheduled cycle after manual wallpaper change.")
    }

    private func deferScheduledCycleIfNeeded(trigger: WallpaperCycleTrigger) -> Bool {
        guard trigger == .scheduled else { return false }
        guard !hasLoggedDeferredScheduledCycle else { return false }
        hasLoggedDeferredScheduledCycle = true
        storeNextScheduledCycleDueAt(Date())
        debugLog("WallpaperCycleController: deferred scheduled cycle until the app is active again.")
        return true
    }

    private func clearDeferredScheduledCycleIfNeeded(trigger: WallpaperCycleTrigger) {
        guard trigger == .scheduled else { return }
        wakeCatchUpTimer?.invalidate()
        wakeCatchUpTimer = nil
        wakeGraceEndsAt = nil
        hasLoggedDeferredScheduledCycle = false
        guard let seconds = frequency?.seconds else {
            clearStoredScheduledCycleDueAt()
            return
        }
        storeNextScheduledCycleDueAt(Date().addingTimeInterval(seconds))
    }

    private func runDeferredScheduledCycleIfNeeded() {
        guard let dueAt = nextScheduledCycleDueAt else { return }
        guard Date() >= dueAt else { return }
        guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
            if !hasLoggedDeferredScheduledCycle {
                hasLoggedDeferredScheduledCycle = true
                debugLog("WallpaperCycleController: deferred scheduled cycle is overdue but this app's user session is not active.")
            }
            return
        }
        guard !screenSleepStateProvider.screensAreAsleep else {
            if !hasLoggedDeferredScheduledCycle {
                hasLoggedDeferredScheduledCycle = true
                debugLog("WallpaperCycleController: deferred scheduled cycle is overdue but the screens are asleep.")
            }
            return
        }
        debugLog("WallpaperCycleController: running deferred scheduled cycle.")
        tick(trigger: .scheduled)
    }

    private func scheduleDeferredScheduledCycleAfterWakeIfNeeded() {
        guard let dueAt = nextScheduledCycleDueAt else { return }
        guard Date() >= dueAt else { return }
        guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
            wakeGraceEndsAt = Date().addingTimeInterval(Self.wakeCatchUpDelay)
            debugLog("WallpaperCycleController: deferred scheduled cycle is overdue after wake; waiting for this app's user session to become active.")
            return
        }
        guard !screenSleepStateProvider.screensAreAsleep else {
            debugLog("WallpaperCycleController: deferred scheduled cycle is overdue after wake but the screens are asleep.")
            scheduleWakeReadinessRetryTimer()
            return
        }
        wakeGraceEndsAt = Date().addingTimeInterval(Self.wakeCatchUpDelay)
        scheduleWakeCatchUpTimer()
    }

    private func scheduleDeferredScheduledCycleAfterSessionActivationIfNeeded() {
        guard let dueAt = nextScheduledCycleDueAt else { return }
        guard Date() >= dueAt else { return }
        guard activeUserSessionProvider.appOwnsActiveConsoleSession else { return }
        guard !screenSleepStateProvider.screensAreAsleep else {
            debugLog("WallpaperCycleController: deferred scheduled cycle is overdue after session activation but the screens are asleep.")
            scheduleWakeReadinessRetryTimer()
            return
        }
        resumeScheduledCycleAfterSessionActivation()
    }

    private func resumeScheduledCycleAfterSessionActivation() {
        wakeCatchUpTimer?.invalidate()
        wakeCatchUpTimer = nil
        wakeGraceEndsAt = nil
        hasLoggedDeferredScheduledCycle = false
        guard let frequency,
              let seconds = frequency.seconds else {
            clearStoredScheduledCycleDueAt()
            return
        }
        timer?.invalidate()
        timer = nil
        storeNextScheduledCycleDueAt(Date().addingTimeInterval(seconds))
        debugLog("WallpaperCycleController: resumed scheduled cycle after session activation; next cycle follows the selected schedule.")
        scheduleTimerTrigger(for: frequency)
    }

    private func shouldDelayScheduledCycleForWakeGrace(trigger: WallpaperCycleTrigger) -> Bool {
        guard trigger == .scheduled,
              let graceEndsAt = wakeGraceEndsAt,
              Date() < graceEndsAt else {
            return false
        }
        debugLog("WallpaperCycleController: delaying overdue scheduled cycle until wake grace period ends.")
        return true
    }

    private func scheduleWakeReadinessRetryTimer() {
        guard wakeCatchUpTimer == nil else { return }
        debugLog("WallpaperCycleController: scheduling overdue wallpaper readiness retry after wake.")
        wakeCatchUpTimer = timerScheduler.scheduledTimer(interval: Self.wakeCatchUpReadinessRetryDelay, repeats: false) { [weak self] in
            Task { @MainActor [weak self] in
                self?.wakeCatchUpTimer = nil
                self?.scheduleDeferredScheduledCycleAfterWakeIfNeeded()
            }
        }
    }

    private func scheduleWakeCatchUpTimer() {
        guard wakeCatchUpTimer == nil else { return }
        debugLog("WallpaperCycleController: scheduling overdue wallpaper catch-up after wake grace period.")
        wakeCatchUpTimer = timerScheduler.scheduledTimer(interval: Self.wakeCatchUpDelay, repeats: false) { [weak self] in
            Task { @MainActor [weak self] in
                self?.wakeCatchUpTimer = nil
                self?.wakeGraceEndsAt = nil
                self?.runDeferredScheduledCycleIfNeeded()
            }
        }
    }

    private func retryPendingAuthorizationCycleIfNeeded() {
        guard let trigger = pendingAuthorizationRetryTrigger else { return }
        pendingAuthorizationRetryTrigger = nil
        debugLog("WallpaperCycleController: retrying wallpaper cycle after Photos authorization changed.")
        tick(trigger: trigger)
    }

    private enum UnavailablePhotosReason {
        case noPhotosAvailable
        case permissionDenied
    }

    private func notifyUnavailablePhotos(reason: UnavailablePhotosReason, trigger: WallpaperCycleTrigger) {
        if !trigger.shouldAlwaysNotifyUnavailablePhotos {
            guard lastAutomaticUnavailablePhotosReason != reason else {
                debugLog("WallpaperCycleController: photo library unavailable for \(reason), automatic notification already shown.")
                return
            }
            lastAutomaticUnavailablePhotosReason = reason
        }

        switch reason {
        case .noPhotosAvailable:
            debugLog("WallpaperCycleController: no photo assets available, posting notification.")
            notifier.notifyNoPhotosAvailable()
        case .permissionDenied:
            debugLog("WallpaperCycleController: Photos permission denied, posting notification.")
            notifier.notifyPhotoLibraryPermissionDenied()
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
