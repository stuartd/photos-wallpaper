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
    
    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo") {
            Picker("Cycle", selection: $cycleController.frequency) {
                ForEach(CycleFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.menu)
            
            Button("Shuffle Now") {
                cycleController.triggerNow()
            }
                    
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

