import Foundation
import SwiftUI
import AppKit
import Combine
import Darwin
import Photos
import Security
import ServiceManagement
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
    func notifyWallpaperChangeFailed()
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
                          title: "No photos available",
                          body: "Photos Wallpaper couldn’t find an available photo in your Photos library.")
    }

    func notifyWallpaperChangeFailed() {
        queueNotification(identifier: "wallpaper-change-failed",
                          title: "Wallpaper could not be changed",
                          body: "The photo could not be loaded or applied. Try Change Wallpaper Now again.")
    }

    func notifyPhotoLibraryPermissionDenied() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Photos access needed"
            alert.informativeText = "Photos Wallpaper does not have permission to read your Photos library.\n\nEnable access in System Settings > Privacy & Security > Photos, then try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Self.openPhotosPrivacySettings()
            }
        }
    }

    private static func openPhotosPrivacySettings() {
        let photosSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Photos")
        let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy")

        if let photosSettingsURL, NSWorkspace.shared.open(photosSettingsURL) {
            return
        }

        if let privacySettingsURL, NSWorkspace.shared.open(privacySettingsURL) {
            return
        }

        debugLog("UserNotificationWallpaperCycleNotifier: failed to open Photos privacy settings.")
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
        debugLog("UserNotificationWallpaperCycleNotifier: notification settings (\(context)): authorization=\(Self.description(for: settings.authorizationStatus)), alerts=\(Self.description(for: settings.alertSetting)), sounds=\(Self.description(for: settings.soundSetting)).")
    }

    private static func description(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private static func description(for setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "not supported"
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

protocol LoginSessionIdentifying {
    var currentLoginSessionIdentifier: Int? { get }
}

protocol StartAtLoginStatusProviding {
    var isStartAtLoginEnabled: Bool { get }
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

struct SecurityLoginSessionIdentifierProvider: LoginSessionIdentifying {
    var currentLoginSessionIdentifier: Int? {
        var sessionID = SecuritySessionId()
        var attributes: SessionAttributeBits = []
        let status = SessionGetInfo(callerSecuritySession, &sessionID, &attributes)
        guard status == errSessionSuccess,
              sessionID != noSecuritySession,
              attributes.contains(.sessionHasGraphicAccess) else {
            return nil
        }
        return Int(sessionID)
    }
}

struct ServiceManagementStartAtLoginStatusProvider: StartAtLoginStatusProviding {
    var isStartAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
            preconditionFailure("The cycle frequency options are out of sync.")
        }
        return option
    }
}

/// The visible shape of a display or photo. Square displays deliberately accept any photo shape.
enum WallpaperOrientation: Hashable {
    case landscape
    case portrait
    case square

    init(size: CGSize) {
        if size.width > size.height {
            self = .landscape
        } else if size.height > size.width {
            self = .portrait
        } else {
            self = .square
        }
    }
}

enum WallpaperPhotoSelector {
    private static let minimumPreferredOrientationProbeCount = 100
    private static let preferredOrientationProbeMultiplier = 50

    /// Selects one asset index for every display. Landscape and portrait displays each probe only
    /// a bounded random subset of the library; square displays accept a randomly selected photo.
    static func indexes(for displayOrientations: [WallpaperOrientation],
                        photoCount: Int,
                        randomIndexInRange: (Range<Int>) -> Int = { Int.random(in: $0) },
                        orientationAtIndex: (Int) -> WallpaperOrientation) -> [Int] {
        guard photoCount > 0, !displayOrientations.isEmpty else { return [] }

        let landscapeIndexes = preferredIndexes(photoCount: photoCount,
                                                count: displayOrientations.filter { $0 == .landscape }.count,
                                                randomIndexInRange: randomIndexInRange) {
            orientationAtIndex($0) == .landscape
        }
        let portraitIndexes = preferredIndexes(photoCount: photoCount,
                                               count: displayOrientations.filter { $0 == .portrait }.count,
                                               randomIndexInRange: randomIndexInRange) {
            orientationAtIndex($0) == .portrait
        }
        let squareIndexes = randomIndexes(photoCount: photoCount,
                                          count: displayOrientations.filter { $0 == .square }.count,
                                          randomIndexInRange: randomIndexInRange)
        var remainingIndexes: [WallpaperOrientation: [Int]] = [
            .landscape: landscapeIndexes,
            .portrait: portraitIndexes,
            .square: squareIndexes
        ]

        return displayOrientations.compactMap { orientation in
            guard var indexes = remainingIndexes[orientation], !indexes.isEmpty else { return nil }
            let index = indexes.removeFirst()
            remainingIndexes[orientation] = indexes
            return index
        }
    }

    private static func preferredIndexes(photoCount: Int,
                                         count: Int,
                                         randomIndexInRange: (Range<Int>) -> Int,
                                         isPreferredOrientation: (Int) -> Bool) -> [Int] {
        guard count > 0 else { return [] }
        let selectionCount = min(count, photoCount)
        let probeLimit = min(photoCount, max(Self.minimumPreferredOrientationProbeCount,
                                             selectionCount * Self.preferredOrientationProbeMultiplier))
        let selectedPreferredIndexes = randomPreferredOrientationIndexes(photoCount: photoCount,
                                                                          count: selectionCount,
                                                                          probeLimit: probeLimit,
                                                                          randomIndexInRange: randomIndexInRange,
                                                                          isPreferredOrientation: isPreferredOrientation)
        let selectedIndexes: [Int]
        if selectedPreferredIndexes.count == selectionCount {
            selectedIndexes = selectedPreferredIndexes
        } else {
            let fallbackIndexes = randomUniqueIndexes(photoCount: photoCount,
                                                      count: selectionCount - selectedPreferredIndexes.count,
                                                      excluding: Set(selectedPreferredIndexes),
                                                      randomIndexInRange: randomIndexInRange)
            selectedIndexes = selectedPreferredIndexes + fallbackIndexes
        }

        guard let fallbackIndex = selectedIndexes.last, selectedIndexes.count < count else {
            return selectedIndexes
        }
        return selectedIndexes + Array(repeating: fallbackIndex, count: count - selectedIndexes.count)
    }

    private static func randomIndexes(photoCount: Int,
                                      count: Int,
                                      randomIndexInRange: (Range<Int>) -> Int) -> [Int] {
        guard count > 0 else { return [] }
        let selectedIndexes = randomUniqueIndexes(photoCount: photoCount,
                                                  count: min(count, photoCount),
                                                  excluding: [],
                                                  randomIndexInRange: randomIndexInRange)
        guard let fallbackIndex = selectedIndexes.last, selectedIndexes.count < count else {
            return selectedIndexes
        }
        return selectedIndexes + Array(repeating: fallbackIndex, count: count - selectedIndexes.count)
    }

    private static func randomPreferredOrientationIndexes(photoCount: Int,
                                                          count: Int,
                                                          probeLimit: Int,
                                                          randomIndexInRange: (Range<Int>) -> Int,
                                                          isPreferredOrientation: (Int) -> Bool) -> [Int] {
        var probedIndexes = Set<Int>()
        var selectedIndexes: [Int] = []
        let attemptLimit = max(probeLimit * 10, 20)
        var attempts = 0

        while probedIndexes.count < probeLimit,
              selectedIndexes.count < count,
              attempts < attemptLimit {
            attempts += 1
            let index = randomIndexInRange(0..<photoCount)
            guard index >= 0,
                  index < photoCount,
                  probedIndexes.insert(index).inserted else {
                continue
            }
            if isPreferredOrientation(index) {
                selectedIndexes.append(index)
            }
        }

        return selectedIndexes
    }

    private static func randomUniqueIndexes(photoCount: Int,
                                            count: Int,
                                            excluding excludedIndexes: Set<Int>,
                                            randomIndexInRange: (Range<Int>) -> Int) -> [Int] {
        let selectionCount = min(count, max(0, photoCount - excludedIndexes.count))
        guard selectionCount > 0 else { return [] }

        var usedIndexes = excludedIndexes
        var selectedIndexes: [Int] = []
        let attemptLimit = max(selectionCount * 10, 20)
        var attempts = 0

        while selectedIndexes.count < selectionCount,
              attempts < attemptLimit {
            attempts += 1
            let index = randomIndexInRange(0..<photoCount)
            guard index >= 0,
                  index < photoCount,
                  usedIndexes.insert(index).inserted else {
                continue
            }
            selectedIndexes.append(index)
        }

        if selectedIndexes.count < selectionCount {
            for index in 0..<photoCount where usedIndexes.insert(index).inserted {
                selectedIndexes.append(index)
                if selectedIndexes.count == selectionCount {
                    break
                }
            }
        }

        return selectedIndexes
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
    private static let lastHandledLoginSessionIdentifierDefaultsKey = "lastHandledLoginSessionIdentifier"
    private static let wakeCatchUpDelay: TimeInterval = 5 * 60
    private static let wakeCatchUpReadinessRetryDelay: TimeInterval = 10
    private static let automaticLoginCycleDebounceInterval: TimeInterval = 10

    @Published var frequency: CycleFrequency? {
        didSet {
            guard hasLoadedInitialFrequency else { return }
            // Persist the newly selected frequency so the next launch resumes the same schedule.
            defaults.set(frequency?.rawValue, forKey: Self.defaultsKey)
            if frequency != oldValue {
                cancelCycle()
                if pendingAuthorizationRetryTrigger != .manual {
                    pendingAuthorizationRetryTrigger = nil
                }
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
    private let loginSessionIdentifierProvider: LoginSessionIdentifying
    private let startAtLoginStatusProvider: StartAtLoginStatusProviding
    private let preflightsPhotoAccessWhenScheduling: Bool
    private let startsScheduleAutomatically: Bool
    private var lastAutomaticUnavailablePhotosReason: UnavailablePhotosReason?
    private var isCycleInProgress = false
    private var cycleID = UUID()
    private var outstandingImages = Set<Int>()
    private var imageRequests: [PhotoImageRequest] = []
    private var imageDeadline: CancellableTimer?
    private let imageDeadlineScheduler: TimerScheduling
    private let now: () -> Date
    private var cycleSucceeded = false
    private var hasLoadedInitialFrequency = false
    private var pendingAuthorizationRetryTrigger: WallpaperCycleTrigger?
    private var isWaitingForSchedulePhotoAuthorization = false
    private var nextScheduledCycleDueAt: Date?
    private var hasLoggedDeferredScheduledCycle = false
    private var wakeGraceEndsAt: Date?
    private var isConfiguringInitialSchedule = true
    private var pendingInitialLoginSessionIdentifier: Int?
    private var isAwaitingActiveSessionAfterLoginScheduleWake = false
    private var lastAutomaticLoginCycleStartedAt: Date?

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
                  loginSessionIdentifierProvider: SecurityLoginSessionIdentifierProvider(),
                  startAtLoginStatusProvider: ServiceManagementStartAtLoginStatusProvider(),
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
                     timerScheduler: TimerScheduling) {
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
                  loginSessionIdentifierProvider: SecurityLoginSessionIdentifierProvider(),
                  startAtLoginStatusProvider: ServiceManagementStartAtLoginStatusProvider(),
                  preflightsPhotoAccessWhenScheduling: true)
    }

    convenience init(photoManager: PhotoManaging,
                     defaults: KeyValueStoring,
                     historyLogger: WallpaperHistoryLogging,
                     notifier: WallpaperCycleNotifying,
                     screenProvider: ScreenProviding,
                     wakeEventObserver: WakeEventObserving,
                     activeUserSessionEventObserver: ActiveUserSessionEventObserving? = nil,
                     timerScheduler: TimerScheduling,
                     screenSleepStateProvider: ScreenSleepStateProviding,
                     activeUserSessionProvider: ActiveUserSessionProviding,
                     preflightsPhotoAccessWhenScheduling: Bool = true,
                     startsScheduleAutomatically: Bool = true) {
        self.init(photoManager: photoManager,
                  defaults: defaults,
                  historyLogger: historyLogger,
                  notifier: notifier,
                  screenProvider: screenProvider,
                  wakeEventObserver: wakeEventObserver,
                  activeUserSessionEventObserver: activeUserSessionEventObserver,
                  timerScheduler: timerScheduler,
                  screenSleepStateProvider: screenSleepStateProvider,
                  activeUserSessionProvider: activeUserSessionProvider,
                  loginSessionIdentifierProvider: SecurityLoginSessionIdentifierProvider(),
                  startAtLoginStatusProvider: ServiceManagementStartAtLoginStatusProvider(),
                  preflightsPhotoAccessWhenScheduling: preflightsPhotoAccessWhenScheduling,
                  startsScheduleAutomatically: startsScheduleAutomatically)
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
         loginSessionIdentifierProvider: LoginSessionIdentifying,
         startAtLoginStatusProvider: StartAtLoginStatusProviding,
         preflightsPhotoAccessWhenScheduling: Bool = true,
         startsScheduleAutomatically: Bool = true,
         imageDeadlineScheduler: TimerScheduling? = nil,
         now: @escaping () -> Date = Date.init) {
        self.imageDeadlineScheduler = imageDeadlineScheduler ?? FoundationTimerScheduler()
        self.now = now
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
        self.loginSessionIdentifierProvider = loginSessionIdentifierProvider
        self.startAtLoginStatusProvider = startAtLoginStatusProvider
        self.preflightsPhotoAccessWhenScheduling = preflightsPhotoAccessWhenScheduling
        self.startsScheduleAutomatically = startsScheduleAutomatically
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let f = CycleFrequency(rawValue: raw) {
            self.frequency = f
        } else {
            self.frequency = nil
        }
        photoManager.addPhotoAuthorizationChangeHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePhotoAuthorizationDidChange()
            }
        }
        hasLoadedInitialFrequency = true
        if startsScheduleAutomatically {
            scheduleCycleTrigger()
        }
        isConfiguringInitialSchedule = false
    }

    // Not ideal, but this will allow the permission tests to run without generating an actual request popup
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil
    }

    /// Runs one wallpaper cycle immediately.
    ///
    /// This is used by the menu command and intentionally shares the same refresh pipeline as
    /// scheduled and wake-triggered cycles.
    func triggerNow() {
        debugLog("WallpaperCycleController: manual wallpaper refresh requested.")
        // `Task {}` starts an async unit of work while keeping the refresh on the main actor.
        Task { @MainActor in
            self.cancelCycle()
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
        pendingInitialLoginSessionIdentifier = nil
        isAwaitingActiveSessionAfterLoginScheduleWake = false
        lastAutomaticLoginCycleStartedAt = nil

        guard let frequency else {
            isWaitingForSchedulePhotoAuthorization = false
            clearStoredScheduledCycleDueAt()
            debugLog("WallpaperCycleController: no wallpaper schedule selected.")
            return
        }
        if preflightsPhotoAccessWhenScheduling {
            switch photoManager.requestPhotoAccessIfNeeded() {
            case .ready:
                isWaitingForSchedulePhotoAuthorization = false
                isWaitingForPhotoAuthorization = false
            case .waitingForAuthorization:
                isWaitingForSchedulePhotoAuthorization = true
                isWaitingForPhotoAuthorization = true
            case .permissionDenied:
                isWaitingForSchedulePhotoAuthorization = false
                isWaitingForPhotoAuthorization = false
                debugLog("WallpaperCycleController: Photos permission denied while configuring schedule.")
                notifyPhotoLibraryPermissionDeniedForScheduleSetup()
            case .unavailable:
                isWaitingForSchedulePhotoAuthorization = false
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
                    self?.handleLoginScheduleSessionBecameActive()
                }
            }
            wakeObservation = wakeEventObserver.observeWake { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleLoginScheduleWake()
                }
            }
            configureLoginCycleAfterScheduleSetup()
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

    private func configureLoginCycleAfterScheduleSetup() {
        guard isConfiguringInitialSchedule else {
            markCurrentLoginSessionHandled()
            return
        }
        runInitialLoginCycleIfNeeded()
    }

    private func runInitialLoginCycleIfNeeded() {
        guard let currentLoginSessionIdentifier = loginSessionIdentifierProvider.currentLoginSessionIdentifier else {
            debugLog("WallpaperCycleController: not running login wallpaper cycle after app launch because the login session could not be identified.")
            return
        }
        guard startAtLoginStatusProvider.isStartAtLoginEnabled else {
            storeHandledLoginSessionIdentifier(currentLoginSessionIdentifier)
            debugLog("WallpaperCycleController: not running login wallpaper cycle after app launch because Start at Login is not enabled.")
            return
        }
        guard defaults.integer(forKey: Self.lastHandledLoginSessionIdentifierDefaultsKey) != currentLoginSessionIdentifier else {
            debugLog("WallpaperCycleController: login wallpaper cycle already handled for this login session.")
            return
        }
        guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
            pendingInitialLoginSessionIdentifier = currentLoginSessionIdentifier
            debugLog("WallpaperCycleController: waiting to run login wallpaper cycle until this app's user session is active.")
            return
        }
        storeHandledLoginSessionIdentifier(currentLoginSessionIdentifier)
        debugLog("WallpaperCycleController: running login wallpaper cycle after app launch.")
        tick(trigger: .login)
    }

    private func handleLoginScheduleSessionBecameActive() {
        if let pendingInitialLoginSessionIdentifier {
            guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
                tick(trigger: .unlock)
                return
            }
            self.pendingInitialLoginSessionIdentifier = nil
            isAwaitingActiveSessionAfterLoginScheduleWake = false
            storeHandledLoginSessionIdentifier(pendingInitialLoginSessionIdentifier)
            debugLog("WallpaperCycleController: running login wallpaper cycle after session activation.")
            tick(trigger: .login)
            return
        }

        if isAwaitingActiveSessionAfterLoginScheduleWake {
            guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
                tick(trigger: .unlock)
                return
            }
            isAwaitingActiveSessionAfterLoginScheduleWake = false
            debugLog("WallpaperCycleController: running wake wallpaper cycle after session activation.")
        }

        tick(trigger: .unlock)
    }

    private func handleLoginScheduleWake() {
        guard !isAwaitingActiveSessionAfterLoginScheduleWake else { return }
        isAwaitingActiveSessionAfterLoginScheduleWake = true
        debugLog("WallpaperCycleController: waiting to run wake wallpaper cycle until this app's user session is active.")
    }

    private func markCurrentLoginSessionHandled() {
        guard let currentLoginSessionIdentifier = loginSessionIdentifierProvider.currentLoginSessionIdentifier else {
            debugLog("WallpaperCycleController: could not remember the current login session for the login wallpaper schedule.")
            return
        }
        storeHandledLoginSessionIdentifier(currentLoginSessionIdentifier)
    }

    private func storeHandledLoginSessionIdentifier(_ identifier: Int) {
        defaults.set(identifier, forKey: Self.lastHandledLoginSessionIdentifierDefaultsKey)
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
            storeNextScheduledCycleDueAt(now().addingTimeInterval(seconds))
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
              now() >= dueAt,
              let seconds = frequency.seconds else {
            return
        }
        hasLoggedDeferredScheduledCycle = false
        storeNextScheduledCycleDueAt(now().addingTimeInterval(seconds))
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
        case login
        case unlock
        case scheduled

        var shouldAlwaysNotifyUnavailablePhotos: Bool {
            self == .manual
        }

        var requiresActiveUserSession: Bool {
            self != .manual
        }

        var isAutomaticLoginScheduleTrigger: Bool {
            switch self {
            case .login, .unlock:
                return true
            case .manual, .scheduled:
                return false
            }
        }

        var logDescription: String {
            switch self {
            case .manual: return "manual"
            case .login: return "login"
            case .unlock: return "unlock"
            case .scheduled: return "scheduled"
            }
        }
    }

    /// Executes one full wallpaper refresh across every connected display.
    ///
    /// The method stays on the main actor because it touches AppKit screen objects and because the
    /// surrounding UI state (`@Published frequency`, notification gating) is actor-isolated.
    private func tick(trigger: WallpaperCycleTrigger, resumingAuthorization: Bool = false) {
        if trigger.requiresActiveUserSession && !activeUserSessionProvider.appOwnsActiveConsoleSession {
            if deferScheduledCycleIfNeeded(trigger: trigger) {
                debugLog("WallpaperCycleController: skipping \(trigger.logDescription) wallpaper cycle because this app's user session is not the active console session.")
            } else if trigger != .scheduled {
                debugLog("WallpaperCycleController: skipping \(trigger.logDescription) wallpaper cycle because this app's user session is not the active console session.")
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
        guard resumingAuthorization || shouldRunAutomaticLoginCycle(trigger: trigger) else { return }
        clearDeferredScheduledCycleIfNeeded(trigger: trigger)
        isCycleInProgress = true
        cycleSucceeded = false
        cycleID = UUID()
        debugLog("WallpaperCycleController: starting \(trigger.logDescription) wallpaper cycle.")
        let screens = screenProvider.screens
        debugLog("WallpaperCycleController: found \(screens.count) screen(s).")
        guard !screens.isEmpty else {
            debugLog("WallpaperCycleController: aborting cycle because no screens were found.")
            finishCycle()
            return
        }
        let assets: [PHAsset]
        let screenSizes = screens.map(\.pixelSize)
        let screenOrientations = screenSizes.map(WallpaperOrientation.init(size:))
        switch photoManager.getRandomPhotos(for: screenOrientations) {
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
        let generation = cycleID
        outstandingImages = Set(screenAssetPairs.map(\.offset))
        imageDeadline = imageDeadlineScheduler.scheduledTimer(interval: 60, repeats: false) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.cycleID == generation, self.isCycleInProgress else { return }
                debugLog("WallpaperCycleController: image deadline expired; cancelling outstanding requests.")
                if trigger == .manual && !self.cycleSucceeded {
                    self.notifier.notifyWallpaperChangeFailed()
                }
                self.cancelCycle()
            }
        }
        for (index, pair) in screenAssetPairs {
            let (screen, asset) = pair
            let displayID = screen.wallpaperDisplayIdentifier
            let screenName = "Screen \(index + 1)"
            let request = photoManager.requestImage(for: asset, targetSize: screenSizes[index]) { [weak self] image in
                guard let self, self.cycleID == generation,
                      self.outstandingImages.remove(index) != nil else { return }
                defer { self.completeImageRequest(trigger: trigger) }
                guard let currentScreen = self.screenProvider.screens.first(where: {
                    $0.wallpaperDisplayIdentifier == displayID
                }) else { return }
                if trigger.requiresActiveUserSession {
                    guard self.frequency != nil,
                          self.activeUserSessionProvider.appOwnsActiveConsoleSession,
                          !self.screenSleepStateProvider.screensAreAsleep else { return }
                }
                guard let image,
                      self.photoManager.setImageAsWallpaper(image, from: asset, for: currentScreen) else { return }
                let appliedAt = self.now()
                self.cycleSucceeded = true
                self.clearDeferredScheduledCycleAfterManualChangeIfNeeded(trigger: trigger)
                // Operational state is recorded before slow human-readable metadata work.
                self.historyLogger.rememberAppliedWallpaper(localIdentifier: self.photoManager.identifier(for: asset),
                                                            displayIdentifier: displayID)
                self.photoManager.requestDisplayName(for: asset) { [historyLogger = self.historyLogger] name in
                    historyLogger.recordWallpaperDetails(photoName: name, screenName: screenName,
                                                         screenCount: screenCount, timestamp: appliedAt)
                }
            }
            // A fake (or a cache hit) may complete synchronously.
            if isCycleInProgress && cycleID == generation {
                imageRequests.append(request)
            } else {
                request.cancel()
            }
        }
    }

    private func clearDeferredScheduledCycleAfterManualChangeIfNeeded(trigger: WallpaperCycleTrigger) {
        guard trigger == .manual,
              let frequency, let seconds = frequency.seconds else {
            return
        }
        wakeCatchUpTimer?.invalidate()
        wakeCatchUpTimer = nil
        wakeGraceEndsAt = nil
        hasLoggedDeferredScheduledCycle = false
        storeNextScheduledCycleDueAt(now().addingTimeInterval(seconds))
        timer?.invalidate()
        scheduleTimerTrigger(for: frequency)
        debugLog("WallpaperCycleController: restarted the schedule after manual wallpaper change.")
    }

    private func deferScheduledCycleIfNeeded(trigger: WallpaperCycleTrigger) -> Bool {
        guard trigger == .scheduled else { return false }
        guard !hasLoggedDeferredScheduledCycle else { return false }
        hasLoggedDeferredScheduledCycle = true
        storeNextScheduledCycleDueAt(now())
        debugLog("WallpaperCycleController: deferred scheduled cycle until this app's user session becomes active.")
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
        storeNextScheduledCycleDueAt(now().addingTimeInterval(seconds))
    }

    private func runDeferredScheduledCycleIfNeeded() {
        guard let dueAt = nextScheduledCycleDueAt else { return }
        guard now() >= dueAt else { return }
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
        guard now() >= dueAt else { return }
        guard activeUserSessionProvider.appOwnsActiveConsoleSession else {
            wakeGraceEndsAt = now().addingTimeInterval(Self.wakeCatchUpDelay)
            debugLog("WallpaperCycleController: deferred scheduled cycle is overdue after wake; waiting for this app's user session to become active.")
            return
        }
        guard !screenSleepStateProvider.screensAreAsleep else {
            debugLog("WallpaperCycleController: deferred scheduled cycle is overdue after wake but the screens are asleep.")
            scheduleWakeReadinessRetryTimer()
            return
        }
        wakeGraceEndsAt = now().addingTimeInterval(Self.wakeCatchUpDelay)
        scheduleWakeCatchUpTimer()
    }

    private func scheduleDeferredScheduledCycleAfterSessionActivationIfNeeded() {
        guard let dueAt = nextScheduledCycleDueAt else { return }
        guard now() >= dueAt else { return }
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
        storeNextScheduledCycleDueAt(now().addingTimeInterval(seconds))
        debugLog("WallpaperCycleController: resumed scheduled cycle after session activation; next cycle follows the selected schedule.")
        scheduleTimerTrigger(for: frequency)
    }

    private func shouldDelayScheduledCycleForWakeGrace(trigger: WallpaperCycleTrigger) -> Bool {
        guard trigger == .scheduled,
              let graceEndsAt = wakeGraceEndsAt,
              now() < graceEndsAt else {
            return false
        }
        debugLog("WallpaperCycleController: delaying overdue scheduled cycle until wake grace period ends.")
        return true
    }

    private func shouldRunAutomaticLoginCycle(trigger: WallpaperCycleTrigger) -> Bool {
        guard frequency == .onLogin,
              trigger.isAutomaticLoginScheduleTrigger else {
            return true
        }

        let currentTime = now()
        if let lastAutomaticLoginCycleStartedAt,
           currentTime.timeIntervalSince(lastAutomaticLoginCycleStartedAt) < Self.automaticLoginCycleDebounceInterval {
            debugLog("WallpaperCycleController: skipping \(trigger.logDescription) wallpaper cycle because another automatic login cycle ran recently.")
            return false
        }

        lastAutomaticLoginCycleStartedAt = currentTime
        return true
    }

    private func scheduleWakeReadinessRetryTimer() {
        guard wakeCatchUpTimer == nil else { return }
        debugLog("WallpaperCycleController: scheduling another screen-readiness check after wake.")
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
        tick(trigger: trigger, resumingAuthorization: true)
    }

    private func handlePhotoAuthorizationDidChange() {
        isWaitingForPhotoAuthorization = false
        let wasWaitingForSchedulePhotoAuthorization = isWaitingForSchedulePhotoAuthorization

        switch photoManager.requestPhotoAccessIfNeeded() {
        case .ready:
            isWaitingForSchedulePhotoAuthorization = false
            retryPendingAuthorizationCycleIfNeeded()
        case .waitingForAuthorization:
            isWaitingForSchedulePhotoAuthorization = wasWaitingForSchedulePhotoAuthorization
            isWaitingForPhotoAuthorization = true
        case .permissionDenied:
            let deniedTrigger = pendingAuthorizationRetryTrigger
            isWaitingForSchedulePhotoAuthorization = false
            pendingAuthorizationRetryTrigger = nil
            if let deniedTrigger {
                notifyUnavailablePhotos(reason: .permissionDenied, trigger: deniedTrigger)
            } else if wasWaitingForSchedulePhotoAuthorization {
                notifyPhotoLibraryPermissionDeniedForScheduleSetup()
            }
        case .unavailable:
            let unavailableTrigger = pendingAuthorizationRetryTrigger
            isWaitingForSchedulePhotoAuthorization = false
            pendingAuthorizationRetryTrigger = nil
            if let unavailableTrigger {
                notifyUnavailablePhotos(reason: .noPhotosAvailable, trigger: unavailableTrigger)
            }
        }
    }

    private func notifyPhotoLibraryPermissionDeniedForScheduleSetup() {
        lastAutomaticUnavailablePhotosReason = .permissionDenied
        notifier.notifyPhotoLibraryPermissionDenied()
    }

    private enum UnavailablePhotosReason {
        case noPhotosAvailable
        case permissionDenied

        var logDescription: String {
            switch self {
            case .noPhotosAvailable:
                return "no photos available"
            case .permissionDenied:
                return "Photos permission denied"
            }
        }
    }

    private func notifyUnavailablePhotos(reason: UnavailablePhotosReason, trigger: WallpaperCycleTrigger) {
        if !trigger.shouldAlwaysNotifyUnavailablePhotos {
            guard lastAutomaticUnavailablePhotosReason != reason else {
                debugLog("WallpaperCycleController: Photos library unavailable (\(reason.logDescription)); the automatic user message was already shown.")
                return
            }
            lastAutomaticUnavailablePhotosReason = reason
        }

        switch reason {
        case .noPhotosAvailable:
            debugLog("WallpaperCycleController: no photo assets are available; showing a notification.")
            notifier.notifyNoPhotosAvailable()
        case .permissionDenied:
            debugLog("WallpaperCycleController: Photos permission is denied; showing an alert.")
            notifier.notifyPhotoLibraryPermissionDenied()
        }
    }

    private func completeImageRequest(trigger: WallpaperCycleTrigger) {
        guard outstandingImages.isEmpty else { return }
        if trigger == .manual && !cycleSucceeded {
            notifier.notifyWallpaperChangeFailed()
        }
        finishCycle()
    }

    private func cancelCycle() {
        // Invalidate the generation before cancellation, which can itself invoke callbacks.
        cycleID = UUID()
        let requests = imageRequests
        finishCycle()
        requests.forEach { $0.cancel() }
    }

    private func finishCycle() {
        imageDeadline?.invalidate()
        imageDeadline = nil
        imageRequests.removeAll()
        outstandingImages.removeAll()
        isCycleInProgress = false
    }

}

extension NSScreen {
    var wallpaperDisplayIdentifier: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "\(frame.origin.x)-\(frame.origin.y)-\(frame.width)-\(frame.height)"
    }

    var pixelSize: CGSize {
        CGSize(width: frame.size.width * backingScaleFactor,
               height: frame.size.height * backingScaleFactor)
    }
}
