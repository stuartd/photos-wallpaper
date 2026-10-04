import Foundation

struct WallpaperCacheFile {
    let url: URL
    let modifiedAt: Date

    var displayIdentifier: String? {
        // Display ID followed by a UUID, then the encoded asset ID. Legacy filenames are
        // still eligible for age-based cleanup, but are never confused with a current URL.
        let name = url.lastPathComponent
        guard name.hasPrefix("current-wallpaper-"), let marker = name.range(of: ".asset-") else { return nil }
        let prefix = String(name[name.index(name.startIndex, offsetBy: 18)..<marker.lowerBound])
        guard prefix.count > 37 else { return nil }
        return String(prefix.dropLast(37))
    }
}

enum WallpaperCachePolicy {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func removableFiles(_ files: [WallpaperCacheFile], protectedURLs: Set<URL>, now: Date) -> [URL] {
        let protected = Set(protectedURLs.map(\.standardizedFileURL))
        var latestByDisplay: [String: WallpaperCacheFile] = [:]
        for file in files {
            guard let display = file.displayIdentifier else { continue }
            if latestByDisplay[display].map({ $0.modifiedAt < file.modifiedAt }) ?? true {
                latestByDisplay[display] = file
            }
        }
        let latest = Set(latestByDisplay.values.map { $0.url.standardizedFileURL })
        return files.filter {
            !protected.contains($0.url.standardizedFileURL)
                && !latest.contains($0.url.standardizedFileURL)
                && now.timeIntervalSince($0.modifiedAt) > retentionInterval
        }.map(\.url)
    }
}
