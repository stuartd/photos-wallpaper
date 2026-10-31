import Foundation

enum AppAboutVersionFormatter {
    static let unavailable = "Unavailable"

    static func versionText(releaseVersion: String?, commit: String?, isLocalBuild: Bool) -> String {
        guard isLocalBuild else {
            return metadataValue(releaseVersion) ?? unavailable
        }
        guard let commit = metadataValue(commit),
              commit.count >= 7,
              commit.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
              }) else {
            return unavailable
        }
        return String(commit.prefix(8))
    }

    private static func metadataValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}
