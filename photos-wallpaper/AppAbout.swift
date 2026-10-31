import AppKit
import SwiftUI

@MainActor
enum AppAbout {
    static let applicationName = "Photos Wallpaper"
    static var title: String { "About \(applicationName)" }
    private static var panel: NSPanel?

    static func show() {
        if panel == nil {
            let contentView = NSHostingView(rootView: PhotosWallpaperAboutView())
            let aboutPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutPanel.title = title
            aboutPanel.isReleasedWhenClosed = false
            aboutPanel.contentView = contentView
            aboutPanel.center()
            panel = aboutPanel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func close() {
        panel?.close()
    }
}

private struct PhotosWallpaperAboutView: View {
    private let bundle = Bundle.main

    private var version: String {
        #if DEBUG
        let isLocalBuild = true
        #else
        let isLocalBuild = bundle.object(forInfoDictionaryKey: "PhotosWallpaperLocalBuild") as? String == "YES"
        #endif
        return AppAboutVersionFormatter.versionText(
            releaseVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            commit: bundle.object(forInfoDictionaryKey: "GitCommit") as? String,
            isLocalBuild: isLocalBuild
        )
    }

    private var appIconImage: NSImage {
        NSImage(named: "AppIcon")
            ?? bundle.image(forResource: "AppIcon")
            ?? NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(AppAbout.applicationName)
                    .font(.system(size: 26, weight: .semibold))
            }

            VStack(spacing: 4) {
                Text("© Stuart Dunkeld 2026")
                Text("Rose Hill Solutions")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Version \(version)")
                Link("photos-wallpaper.app", destination: URL(string: "https://photos-wallpaper.app")!)
            }
            .font(.system(size: 14))
            .textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 380)
        .onExitCommand(perform: AppAbout.close)
    }
}
