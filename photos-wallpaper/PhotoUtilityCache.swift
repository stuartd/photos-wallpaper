import Foundation

/// Successful classifications only, versioned by the asset's last edit and our analysis recipe.
/// The file is bounded and contains identifiers and booleans, never image data or aesthetic scores.
nonisolated struct PhotoUtilityCache {
    struct Entry: Codable {
        let modificationDate: Date?
        let isUtility: Bool
        let classifiedAt: Date
    }
    private struct FileContents: Codable {
        let recipe: Int
        let entries: [String: Entry]
    }
    private(set) var entries: [String: Entry] = [:]
    private let url: URL?
    private let capacity: Int

    init(url: URL?, capacity: Int = 2_000) {
        self.url = url
        self.capacity = capacity
        if let url, let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(FileContents.self, from: data), file.recipe == 1 {
            entries = file.entries
            trim()
        }
    }

    func result(for candidate: WallpaperPhotoCandidate) -> Bool? {
        guard let entry = entries[candidate.identifier],
              entry.modificationDate == candidate.modificationDate else { return nil }
        return entry.isUtility
    }

    mutating func record(_ utility: Bool, for candidate: WallpaperPhotoCandidate) {
        entries[candidate.identifier] = Entry(modificationDate: candidate.modificationDate,
                                             isUtility: utility, classifiedAt: Date())
        trim()
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(FileContents(recipe: 1, entries: entries))
            try data.write(to: url, options: .atomic)
        } catch {
            // Classification remains useful in memory even if local persistence is unavailable.
            Task { @MainActor in debugLog("Photo utility cache could not be saved: \(error.localizedDescription)") }
        }
    }

    private mutating func trim() {
        if entries.count > capacity {
            let oldest = entries.sorted { $0.value.classifiedAt < $1.value.classifiedAt }
            for entry in oldest.prefix(entries.count - capacity) { entries.removeValue(forKey: entry.key) }
        }
    }
}

