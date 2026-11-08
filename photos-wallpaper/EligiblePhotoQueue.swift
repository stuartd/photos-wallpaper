import Foundation

/// Metadata only. No thumbnails, decoded images, or wallpaper files live in this queue.
nonisolated struct WallpaperPhotoCandidate: Equatable, Sendable {
    let identifier: String
    let modificationDate: Date?
    let orientation: WallpaperOrientation
    let isScreenshot: Bool
}

// The app target defaults to MainActor; providers use their own actors for Photos/Vision work.
nonisolated protocol WallpaperCandidateProviding: Sendable {
    func candidates(limit: Int, excluding: Set<String>) async -> [WallpaperPhotoCandidate]
    func isUtility(_ candidate: WallpaperPhotoCandidate) async -> Bool?
    func currentCandidates(_ candidates: [WallpaperPhotoCandidate]) async -> [WallpaperPhotoCandidate]
}

@MainActor
final class EligiblePhotoQueue {
    static let capacity = 10
    static let searchLimit = 100
    private let source: any WallpaperCandidateProviding
    private(set) var ready: [WallpaperPhotoCandidate] = []
    private var refill: Task<Void, Never>?
    private var generation = UUID()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    // Failures are not persisted or retried in this session, unless the asset is edited.
    private var failedVersions: [String: WallpaperPhotoCandidate] = [:]

    init(source: any WallpaperCandidateProviding) { self.source = source }

    func invalidate() {
        generation = UUID()
        refill?.cancel()
        refill = nil
        ready.removeAll()
        wakeWaiters()
    }

    func prewarm() {
        guard refill == nil, ready.count < Self.capacity else { return }
        let token = generation
        refill = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(20)
            let candidates = await source.candidates(limit: Self.searchLimit,
                excluding: Set(ready.map(\.identifier)))
            for candidate in candidates {
                guard !Task.isCancelled, generation == token,
                      Date() < deadline, ready.count < Self.capacity else { break }
                guard !candidate.isScreenshot,
                      failedVersions[candidate.identifier] != candidate else { continue }
                let utility = await source.isUtility(candidate)
                guard !Task.isCancelled, generation == token else { break }
                if let utility {
                    if !utility {
                        ready.append(candidate)
                        wakeWaiters()
                    }
                } else {
                    failedVersions[candidate.identifier] = candidate
                }
            }
            guard generation == token else { return }
            refill = nil
            wakeWaiters()
        }
    }

    func take(for orientations: [WallpaperOrientation]) async -> [WallpaperPhotoCandidate] {
        guard !orientations.isEmpty else { return [] }
        let token = generation
        if ready.isEmpty {
            prewarm()
            // Wake as soon as the first eligible reference is ready, not after filling all ten.
            await withCheckedContinuation { waiters.append($0) }
        }
        guard !Task.isCancelled, token == generation else { return [] }
        let snapshot = ready
        let current = await source.currentCandidates(snapshot)
        guard !Task.isCancelled, token == generation else { return [] }
        let valid = Set(current.map(\.identifier))
        ready.removeAll { snapshot.contains($0) && !valid.contains($0.identifier) }
        var selected: [WallpaperPhotoCandidate] = []
        for orientation in orientations {
            let available = ready.indices.filter { valid.contains(ready[$0].identifier) }
            if let fallbackIndex = available.first {
                let index = available.first { orientation == .square || ready[$0].orientation == orientation } ?? fallbackIndex
                selected.append(ready.remove(at: index))
            } else if let fallback = selected.first {
                // A small eligible library can still serve every display.
                selected.append(fallback)
            }
        }
        if !selected.isEmpty { prewarm() }
        return selected
    }

    private func wakeWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
