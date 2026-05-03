//
//  photos_wallpaperApp.swift
//  photos-wallpaper
//
//  Created by Stuart on 28/04/2026.
//

import SwiftUI
import Photos

@main
struct photos_wallpaperApp: App {
    @StateObject private var cycleController = WallpaperCycleController()
    
    /// Builds the menu bar scene that exposes the wallpaper cycle controls and delegates actions into the controller chain.
    var body: some Scene {
        // Create a menu bar extra so the app lives in the macOS menu bar instead of a standard window.
        MenuBarExtra("Wallpaper", systemImage: "photo") {
            // Present a picker that binds directly to the controller's persisted cycle frequency.
            Picker("Cycle", selection: $cycleController.frequency) {
                // Render one menu item for each available cycling frequency.
                ForEach(CycleFrequency.allCases) { freq in
                    // Show the display name and bind the row to the enum case it represents.
                    Text(freq.displayName).tag(freq)
                }
            }
            // Render the picker using standard menu-style presentation in the menu bar popover.
            .pickerStyle(.menu)
            
            // Offer a manual shuffle action that bypasses the timer and runs the update chain immediately.
            Button("Shuffle Now") {
                // Ask the controller to execute the same wallpaper update path used by the scheduled timer.
                cycleController.triggerNow()
            }
                    
            // Visually separate the wallpaper controls from the app lifecycle action below.
            Divider()
            
            // Provide a quit action so the user can terminate the menu bar app.
            Button("Quit") {
                // Ask AppKit to terminate the application process.
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
