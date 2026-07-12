//
//  photos_wallpaperApp.swift
//  photos-wallpaper
//
//  Created by Stuart on 28/04/2026.
//

import SwiftUI
import Photos
import AppKit
import Combine
import Darwin

@MainActor
protocol AppModalWindowProviding {
    var hasModalWindow: Bool { get }
}

struct AppKitModalWindowProvider: AppModalWindowProviding {
    var hasModalWindow: Bool {
        NSApp.modalWindow != nil
    }
}

@MainActor
protocol FirstRunWelcomeScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
}

struct MainQueueFirstRunWelcomeScheduler: FirstRunWelcomeScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                action()
            }
        }
    }
}

@MainActor
final class FirstRunStartupController: ObservableObject {
    private static let initialWelcomeDelay: TimeInterval = 1
    private static let modalRetryDelay: TimeInterval = 0.5

    private let firstRunNotifier: FirstRunNotifier
    private let modalWindowProvider: AppModalWindowProviding
    private let welcomeScheduler: FirstRunWelcomeScheduling
    private var didScheduleWelcome = false

    init(firstRunNotifier: FirstRunNotifier? = nil,
         modalWindowProvider: AppModalWindowProviding? = nil,
         welcomeScheduler: FirstRunWelcomeScheduling? = nil) {
        self.firstRunNotifier = firstRunNotifier ?? FirstRunNotifier()
        self.modalWindowProvider = modalWindowProvider ?? AppKitModalWindowProvider()
        self.welcomeScheduler = welcomeScheduler ?? MainQueueFirstRunWelcomeScheduler()
    }

    func scheduleWelcomeIfNeeded() {
        guard !didScheduleWelcome else { return }
        didScheduleWelcome = true

        debugLog("FirstRunStartupController: scheduling first-run welcome.")
        scheduleWelcomeAttempt(after: Self.initialWelcomeDelay)
    }

    func dismissWelcomeIfPresented() {
        firstRunNotifier.dismissWelcomeIfPresented()
    }

    private func scheduleWelcomeAttempt(after delay: TimeInterval) {
        welcomeScheduler.schedule(after: delay) { [weak self] in
            self?.presentWelcomeWhenReady()
        }
    }

    private func presentWelcomeWhenReady() {
        guard !modalWindowProvider.hasModalWindow else {
            debugLog("FirstRunStartupController: delaying first-run welcome because a modal window is open.")
            scheduleWelcomeAttempt(after: Self.modalRetryDelay)
            return
        }

        firstRunNotifier.notifyIfNeeded()
    }
}

@main
/// The app is just a menu bar extra plus a long-lived controller.
///
/// `@StateObject` means SwiftUI creates the controller once for the app lifetime rather than
/// recreating it every time the menu UI is redrawn.
///
/// Quick SwiftUI glossary:
/// - `App`: the SwiftUI entry point, roughly comparable to the app delegate/bootstrap layer.
/// - `@StateObject`: "SwiftUI owns this reference-type object and should keep it alive for me."
/// - `Binding`: a two-way value connection, so UI changes update the model and model changes update
///   the UI.
struct photos_wallpaperApp: App {
    /// Retains the POSIX lock for the app lifetime.
    private let singleInstanceLock: SingleInstanceLock?
    @StateObject private var firstRunStartupController: FirstRunStartupController
    @StateObject private var cycleController: WallpaperCycleController
    @StateObject private var currentWallpaperAlbumController: CurrentWallpaperAlbumController
    @StateObject private var loginItemManager = LoginItemManager()
    @State private var isAboutPanelOpen = false
    @State private var pendingStartAtLoginPromptFrequency: CycleFrequency?
    @State private var isStartAtLoginPromptRetryScheduled = false
    private let historyLogger: WallpaperHistoryLogger
    private let runtimeLogger = AppRuntimeLogger.shared
    private let documentOpener = AppDocumentOpener()

    init() {
        self.singleInstanceLock = Self.acquireSingleInstanceLock()

        let firstRunStartupController = FirstRunStartupController()
        let historyLogger = WallpaperHistoryLogger()
        _firstRunStartupController = StateObject(wrappedValue: firstRunStartupController)
        self.historyLogger = historyLogger
        _currentWallpaperAlbumController = StateObject(wrappedValue: CurrentWallpaperAlbumController(historyLogger: historyLogger))
        _cycleController = StateObject(wrappedValue: WallpaperCycleController(historyLogger: historyLogger))
        firstRunStartupController.scheduleWelcomeIfNeeded()
    }

    private static func acquireSingleInstanceLock() -> SingleInstanceLock? {
        switch SingleInstanceLock.acquire() {
        case .acquired(let lock):
            debugLog("photos_wallpaperApp: acquired single-instance lock at \(lock.lockURL.path).")
            return lock
        case .alreadyLocked:
            debugLog("photos_wallpaperApp: another instance is already running; terminating this launch.")
            ExistingAppInstanceActivator().activateExistingInstance()
            Darwin.exit(EXIT_SUCCESS)
        case .failed(let error):
            debugLog("photos_wallpaperApp: could not acquire single-instance lock: \(error.localizedDescription).")
            return nil
        }
    }

    var body: some Scene {
        MenuBarExtra("Photos Wallpaper", systemImage: "photo") {
            Picker("Set Schedule", selection: frequencyBinding) {
                Text("No Schedule").tag(Optional<CycleFrequency>.none)
                ForEach(CycleFrequency.allCases) { freq in
                    Text(freq.displayName).tag(Optional(freq))
                }
            }
            .pickerStyle(.menu)
            .disabled(isMenuInteractionDisabled)
            .onAppear {
                prepareForUserInitiatedSurface()
                promptToEnableStartAtLoginIfNeeded(for: cycleController.frequency)
            }
            .onChange(of: cycleController.isWaitingForPhotoAuthorization) { _, isWaiting in
                guard !isWaiting else { return }
                guard pendingStartAtLoginPromptFrequency != nil else { return }
                promptToEnableStartAtLoginIfNeeded(for: cycleController.frequency)
            }

            Button("Change Wallpaper Now") {
                prepareForUserInitiatedSurface()
                cycleController.triggerNow()
            }
            .disabled(isMenuInteractionDisabled)

            Button("Add Current Wallpaper to Photos Wallpaper Album") {
                prepareForUserInitiatedSurface()
                currentWallpaperAlbumController.addCurrentWallpapersToAlbum()
            }
            .disabled(isMenuInteractionDisabled)

            Toggle("Start at Login", isOn: startAtLoginBinding)
                .disabled(isMenuInteractionDisabled)

            Divider()

            Menu("About & Support") {
                Button("Contact Support…") {
                    prepareForUserInitiatedSurface()
                    documentOpener.openSupportPage()
                }

                Button("Privacy Policy") {
                    prepareForUserInitiatedSurface()
                    documentOpener.openPrivacyDocument()
                }

                Menu("Logs") {
                    Button("Show Wallpaper History") {
                        prepareForUserInitiatedSurface()
                        historyLogger.openHistoryLog()
                    }

                    Button("Show Runtime Log") {
                        prepareForUserInitiatedSurface()
                        runtimeLogger.openRuntimeLog()
                    }
                }

                Divider()

                Button("About Photos Wallpaper") {
                    prepareForUserInitiatedSurface()
                    isAboutPanelOpen = true
                    defer { isAboutPanelOpen = false }
                    documentOpener.openAboutPanel()
                }
            }
            .disabled(isMenuInteractionDisabled)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .disabled(isMenuInteractionDisabled)
        }
    }

    private var isMenuInteractionDisabled: Bool {
        isAboutPanelOpen || currentWallpaperAlbumController.isPresentingAlert
    }

    private var frequencyBinding: Binding<CycleFrequency?> {
        Binding(
            get: { cycleController.frequency },
            set: { newFrequency in
                prepareForUserInitiatedSurface()
                cycleController.frequency = newFrequency
                promptToEnableStartAtLoginIfNeeded(for: cycleController.frequency)
            }
        )
    }

    private var startAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { isEnabled in
                prepareForUserInitiatedSurface()
                loginItemManager.setEnabled(isEnabled)
            }
        )
    }

    private func prepareForUserInitiatedSurface() {
        firstRunStartupController.dismissWelcomeIfPresented()
    }

    private func promptToEnableStartAtLoginIfNeeded(for frequency: CycleFrequency?) {
        guard !cycleController.isWaitingForPhotoAuthorization else {
            pendingStartAtLoginPromptFrequency = frequency
            scheduleStartAtLoginPromptRetry()
            return
        }
        pendingStartAtLoginPromptFrequency = nil
        DispatchQueue.main.async {
            prepareForUserInitiatedSurface()
            loginItemManager.promptToEnableStartAtLogin(forSchedule: frequency?.rawValue)
        }
    }

    private func scheduleStartAtLoginPromptRetry() {
        guard !isStartAtLoginPromptRetryScheduled else { return }
        isStartAtLoginPromptRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isStartAtLoginPromptRetryScheduled = false
            guard pendingStartAtLoginPromptFrequency != nil else { return }
            promptToEnableStartAtLoginIfNeeded(for: cycleController.frequency)
        }
    }
}
