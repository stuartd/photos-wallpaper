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
    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo") {
            Button("Shuffle Now") {
                WallpaperManager.shared.setRandomPhotoAsWallpaper()
            }
        
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
