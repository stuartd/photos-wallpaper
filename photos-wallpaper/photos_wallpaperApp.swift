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
/// - `$cycleController.frequency`: a two-way binding, so UI changes update the model and model
///   changes update the UI.
struct photos_wallpaperApp: App {
    @StateObject private var cycleController = WallpaperCycleController()
    private let historyLogger = WallpaperHistoryLogger()
    private let documentOpener = AppDocumentOpener()

    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo") {
            Picker("Cycle", selection: $cycleController.frequency) {
                ForEach(CycleFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.menu)

            Button("Set wallpaper now") {
                cycleController.triggerNow()
            }

            Button("Show wallpaper history") {
                historyLogger.openHistoryLog()
            }

            Divider()

            Button("About Photos Wallpaper") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [:])
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("Privacy") {
                documentOpener.openPrivacyDocument()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
