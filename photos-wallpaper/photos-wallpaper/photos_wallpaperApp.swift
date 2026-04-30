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
                if let asset = PhotoManager.shared.getRandomPhoto() {
                    let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                    PhotoManager.shared.requestImage(for: asset, targetSize: size) { image in
                        if let image = image {
                            PhotoManager.shared.setImageAsWallpaper(image)
                        }
                    }
                }
            }
                    
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
