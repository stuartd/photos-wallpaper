import Foundation
import SwiftUI
import AppKit
import Combine

public enum CycleFrequency: String, CaseIterable, Identifiable {
    case second
    case minute
    case hour
    case day

    public var id: String { rawValue }

    public var seconds: TimeInterval {
        switch self {
        case .second: return 1
        case .minute: return 60
        case .hour: return 60 * 60
        case .day: return 60 * 60 * 24
        }
    }

    public var displayName: String {
        switch self {
        case .second: return "Every second"
        case .minute: return "Every minute"
        case .hour: return "Every hour"
        case .day: return "Every day"
        }
    }
}

@MainActor public final class WallpaperCycleController: ObservableObject {
    private static let defaultsKey = "cycleFrequency"

    @Published public var frequency: CycleFrequency {
        didSet {
            UserDefaults.standard.set(frequency.rawValue, forKey: Self.defaultsKey)
            rescheduleTimer()
        }
    }

    private var timer: Timer?

    public init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let f = CycleFrequency(rawValue: raw) {
            self.frequency = f
        } else {
            self.frequency = .hour
        }
        scheduleTimer()
    }

    public func triggerNow() {
        Task { @MainActor in
            self.tick()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frequency.seconds, repeats: true) { [weak self] _ in
            let controller = self
            Task { @MainActor in
                controller?.tick()
            }
        }
    }

    private func rescheduleTimer() {
        scheduleTimer()
    }

    private func tick() {
        guard let asset = PhotoManager.shared.getRandomPhoto() else { return }
        let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        PhotoManager.shared.requestImage(for: asset, targetSize: size) { image in
            if let image = image {
                PhotoManager.shared.setImageAsWallpaper(image)
            }
        }
    }
}
