import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func localAboutVersionUsesEightCharacterCommit() {
        #expect(AppAboutVersionFormatter.versionText(
            releaseVersion: "2.0", commit: "abcdef0123456789", isLocalBuild: true) == "abcdef01")
    }

    @Test func publishedAboutVersionUsesAppVersionInsteadOfCommit() {
        #expect(AppAboutVersionFormatter.versionText(
            releaseVersion: "2.0", commit: "abcdef0123456789", isLocalBuild: false) == "2.0")
    }

    @Test func aboutVersionTrimsBuildMetadata() {
        #expect(AppAboutVersionFormatter.versionText(
            releaseVersion: " 2.0\n", commit: nil, isLocalBuild: false) == "2.0")
        #expect(AppAboutVersionFormatter.versionText(
            releaseVersion: nil, commit: " ABCDEF0123456789\n", isLocalBuild: true) == "ABCDEF01")
    }

    @Test func localAboutVersionRejectsMissingOrInvalidCommit() {
        for commit: String? in [nil, "", "abcdef", "preview", "$(GIT_COMMIT)"] {
            #expect(AppAboutVersionFormatter.versionText(
                releaseVersion: "2.0", commit: commit, isLocalBuild: true) == AppAboutVersionFormatter.unavailable)
        }
    }

    @Test func publishedAboutVersionRejectsMissingOrUnexpandedVersion() {
        for version: String? in [nil, "", " \n", "$(MARKETING_VERSION)"] {
            #expect(AppAboutVersionFormatter.versionText(
                releaseVersion: version, commit: "abcdef0123456789", isLocalBuild: false) == AppAboutVersionFormatter.unavailable)
        }
    }
}
