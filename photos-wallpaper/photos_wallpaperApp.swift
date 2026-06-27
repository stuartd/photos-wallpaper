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

@MainActor
final class FirstRunStartupController: ObservableObject {
    private let firstRunNotifier = FirstRunNotifier()
    private var didScheduleWelcome = false

    func scheduleWelcomeIfNeeded() {
        guard !didScheduleWelcome else { return }
        didScheduleWelcome = true

        debugLog("FirstRunStartupController: scheduling first-run welcome.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.firstRunNotifier.notifyIfNeeded()
        }
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
    @StateObject private var firstRunStartupController: FirstRunStartupController
    @StateObject private var cycleController: WallpaperCycleController
    @StateObject private var loginItemManager = LoginItemManager()
    @State private var isAboutPanelOpen = false
    @State private var pendingStartAtLoginPromptFrequency: CycleFrequency?
    @State private var isStartAtLoginPromptRetryScheduled = false
    private let historyLogger: WallpaperHistoryLogger
    private let runtimeLogger = AppRuntimeLogger.shared
    private let documentOpener = AppDocumentOpener()
    private let currentWallpaperAlbumController: CurrentWallpaperAlbumController

    init() {
        let firstRunStartupController = FirstRunStartupController()
        let historyLogger = WallpaperHistoryLogger()
        _firstRunStartupController = StateObject(wrappedValue: firstRunStartupController)
        self.historyLogger = historyLogger
        self.currentWallpaperAlbumController = CurrentWallpaperAlbumController(historyLogger: historyLogger)
        _cycleController = StateObject(wrappedValue: WallpaperCycleController(historyLogger: historyLogger))
        firstRunStartupController.scheduleWelcomeIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo") {
            Picker("Wallpaper Schedule", selection: frequencyBinding) {
                ForEach(CycleFrequency.allCases) { freq in
                    Text(freq.displayName).tag(Optional(freq))
                }
            }
            .pickerStyle(.menu)
            .disabled(isAboutPanelOpen)
            .onAppear {
                promptToEnableStartAtLoginIfNeeded(for: cycleController.frequency)
            }
            .onChange(of: cycleController.isWaitingForPhotoAuthorization) { _, isWaiting in
                guard !isWaiting else { return }
                promptToEnableStartAtLoginIfNeeded(for: pendingStartAtLoginPromptFrequency)
            }

            Toggle("Start at Login", isOn: startAtLoginBinding)
                .disabled(isAboutPanelOpen)

            Button("Change Wallpaper Now") {
                cycleController.triggerNow()
            }
            .disabled(isAboutPanelOpen)

            Button("Add Current Wallpaper(s) to Photos Wallpaper Album") {
                currentWallpaperAlbumController.addCurrentWallpapersToAlbum()
            }
            .disabled(isAboutPanelOpen)

            Menu("Logs") {
                Button("Show Wallpaper History") {
                    historyLogger.openHistoryLog()
                }

                Button("Show Runtime Log") {
                    runtimeLogger.openRuntimeLog()
                }
            }
            .disabled(isAboutPanelOpen)

            Divider()

            Button("About Photos Wallpaper") {
                isAboutPanelOpen = true
                defer { isAboutPanelOpen = false }
                documentOpener.openAboutPanel()
            }
            .disabled(isAboutPanelOpen)

            Divider()

            Button("Privacy Policy") {
                documentOpener.openPrivacyDocument()
            }
            .disabled(isAboutPanelOpen)

            Button("Contact Support…") {
                documentOpener.openSupportPage()
            }
            .disabled(isAboutPanelOpen)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var frequencyBinding: Binding<CycleFrequency?> {
        Binding(
            get: { cycleController.frequency },
            set: { newFrequency in
                cycleController.frequency = newFrequency
                promptToEnableStartAtLoginIfNeeded(for: newFrequency)
            }
        )
    }

    private var startAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { loginItemManager.setEnabled($0) }
        )
    }

    private func promptToEnableStartAtLoginIfNeeded(for frequency: CycleFrequency?) {
        guard !cycleController.isWaitingForPhotoAuthorization else {
            pendingStartAtLoginPromptFrequency = frequency
            scheduleStartAtLoginPromptRetry()
            return
        }
        pendingStartAtLoginPromptFrequency = nil
        DispatchQueue.main.async {
            loginItemManager.promptToEnableStartAtLogin(forSchedule: frequency?.rawValue)
        }
    }

    private func scheduleStartAtLoginPromptRetry() {
        guard !isStartAtLoginPromptRetryScheduled else { return }
        isStartAtLoginPromptRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isStartAtLoginPromptRetryScheduled = false
            guard let pendingStartAtLoginPromptFrequency else { return }
            promptToEnableStartAtLoginIfNeeded(for: pendingStartAtLoginPromptFrequency)
        }
    }
}
