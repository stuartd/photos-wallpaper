//
//  Photo_WallPaperApp.swift
//  Photo Wallpaper
//
//  Created by Stuart Dunkeld on 25/04/2026.
//

import SwiftUI
import Photos
import AppKit
import Foundation

@main
struct PhotoWallpaperApp: App {
    var body: some Scene {
        MenuBarExtra("Photo Wallpaper", systemImage: "photo") {
            Button("Change Wallpaper") {
                showMessage()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

func showMessage() {
    let alert = NSAlert()
    alert.messageText = "Change wallpaper?"
    alert.informativeText = "This will pick a random photo."
    alert.alertStyle = .warning

    alert.addButton(withTitle: "Go on then")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
        print("User confirmed")
    }
}

/*
class WallpaperManager: ObservableObject {
    @Published var isActive: Bool = false
    
    private var timer: Timer?
    
    func startChangingWallpaper(every interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.changeWallpaper()
        }
    }

    func changeWallpaper() {
        // Pick a random photo and set as desktop wallpaper
    }
}
*/
