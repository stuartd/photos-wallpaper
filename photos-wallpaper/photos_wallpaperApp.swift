//
//  photos_wallpaperApp.swift
//  photos-wallpaper
//
//  Created by Stuart on 28/04/2026.
//

import SwiftUI
import Photos
import AppKit

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
    @StateObject private var cycleController = WallpaperCycleController()
    @StateObject private var loginItemManager = LoginItemManager()
    @State private var isAboutPanelOpen = false
    private let historyLogger = WallpaperHistoryLogger()
    private let runtimeLogger = AppRuntimeLogger.shared
    private let documentOpener = AppDocumentOpener()

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

            Toggle("Start at Login", isOn: startAtLoginBinding)
                .disabled(isAboutPanelOpen)

            Button("Change wallpaper now") {
                cycleController.triggerNow()
            }
            .disabled(isAboutPanelOpen)

            Button("Show wallpaper history") {
                historyLogger.openHistoryLog()
            }
            .disabled(isAboutPanelOpen)

            Button("Show Diagnostic Log") {
                runtimeLogger.openRuntimeLog()
            }
            .disabled(isAboutPanelOpen)

            Divider()

            Button("About Photos Wallpaper") {
                isAboutPanelOpen = true
                defer { isAboutPanelOpen = false }
                documentOpener.openAboutPanel()
            }
            .disabled(isAboutPanelOpen)

            Button("Privacy") {
                documentOpener.openPrivacyDocument()
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
        DispatchQueue.main.async {
            loginItemManager.promptToEnableStartAtLogin(forSchedule: frequency?.rawValue)
        }
    }
}
