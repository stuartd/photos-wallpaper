import Foundation
import Testing
@testable import photos_wallpaper

extension PhotosWallpaperTests {
    @Test func queueHoldsTenReferencesAndRefillsAfterConsumption() async {
        let source = FakeWallpaperCandidateSource(photos: (0..<30).map { candidate("photo-\($0)") })
        let queue = EligiblePhotoQueue(source: source)
        queue.prewarm()
        #expect(await waitForCondition { queue.ready.count == 10 })
        let first = await queue.take(for: [.landscape, .portrait])
        #expect(first.count == 2)
        #expect(Set(first.map(\.identifier)).count == 2)
        #expect(await waitForCondition { queue.ready.count == 10 })
        queue.invalidate()
    }

    @Test func queueSkipsScreenshotsUtilityAndFailuresWithoutRetryingFailures() async {
        let source = FakeWallpaperCandidateSource(photos: [
            candidate("screenshot", screenshot: true), candidate("receipt"), candidate("failure"), candidate("photo")
        ], utility: ["receipt"], failures: ["failure"])
        let queue = EligiblePhotoQueue(source: source)
        let result = await queue.take(for: [.landscape])
        #expect(result.map(\.identifier) == ["photo"])
        // Wait for the small refill to finish before starting another request.
        await source.waitForCalls(atLeast: 4)
        _ = await queue.take(for: [.landscape])
        let calls = await source.classifications
        #expect(!calls.contains("screenshot"))
        #expect(calls.filter { $0 == "failure" }.count == 1)
        queue.invalidate()
    }

    @Test func utilityOnlyLibraryStopsAtSearchBoundAndReturnsNoPhoto() async {
        let photos = (0..<1_000).map { candidate("utility-\($0)") }
        let source = FakeWallpaperCandidateSource(photos: photos, utility: Set(photos.map(\.identifier)))
        let queue = EligiblePhotoQueue(source: source)
        let result = await queue.take(for: [.landscape])
        let calls = await source.classifications
        #expect(result.isEmpty)
        #expect(calls.count == EligiblePhotoQueue.searchLimit)
        queue.invalidate()
    }

    @Test func queueDropsDeletedOrEditedReferencesBeforeUse() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("deleted"), candidate("edited")])
        let queue = EligiblePhotoQueue(source: source)
        queue.prewarm()
        #expect(await waitForCondition { queue.ready.count == 2 })
        await source.hide(["deleted", "edited"])
        #expect(await queue.take(for: [.landscape]) == [])
        queue.invalidate()
    }

    @Test func coldQueueReturnsFirstPhotoWhileRemainingClassificationIsPending() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("first"), candidate("slow")], blocked: "slow")
        let queue = EligiblePhotoQueue(source: source)
        let result = await queue.take(for: [.landscape, .portrait])
        #expect(result.map(\.identifier) == ["first", "first"])
        await source.release()
        queue.invalidate()
    }

    @Test func invalidationDiscardsLateClassification() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("slow")], blocked: "slow")
        let queue = EligiblePhotoQueue(source: source)
        queue.prewarm()
        await source.waitForCalls(atLeast: 1)
        queue.invalidate()
        await source.release()
        await Task.yield()
        #expect(queue.ready.isEmpty)
    }

    @Test func cancelledSelectionDoesNotConsumeLateEligibleReference() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("slow")], blocked: "slow")
        let queue = EligiblePhotoQueue(source: source)
        let selection = Task { await queue.take(for: [.landscape]) }
        await source.waitForCalls(atLeast: 1)
        selection.cancel()
        await source.release()
        #expect(await selection.value.isEmpty)
        #expect(queue.ready.map(\.identifier) == ["slow"])
        queue.invalidate()
    }

    @Test func failedClassificationCanBeRetriedAfterPhotoIsEdited() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("edited")], failures: ["edited"])
        let queue = EligiblePhotoQueue(source: source)
        #expect(await queue.take(for: [.landscape]).isEmpty)
        queue.invalidate()
        #expect(await queue.take(for: [.landscape]).isEmpty)
        #expect(await source.classifications.count == 1)
        let edited = candidate("edited", modified: Date(timeIntervalSince1970: 1))
        await source.edit(edited)
        queue.invalidate()
        #expect(await queue.take(for: [.landscape]) == [edited])
        #expect(await source.classifications.count == 2)
        queue.invalidate()
    }

    @Test func queuePrefersMatchingOrientationAmongEligibleReferences() async {
        let source = FakeWallpaperCandidateSource(photos: [candidate("wide"), candidate("tall", orientation: .portrait)])
        let queue = EligiblePhotoQueue(source: source)
        queue.prewarm()
        #expect(await waitForCondition { queue.ready.count == 2 })
        let result = await queue.take(for: [.portrait, .landscape])
        #expect(result.map(\.identifier) == ["tall", "wide"])
        queue.invalidate()
    }

    @Test func utilityCachePersistsSuccessAndInvalidatesEditedAsset() throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("classifications.json")
        var cache = PhotoUtilityCache(url: url)
        let photo = candidate("photo")
        cache.record(false, for: photo)
        cache.record(true, for: candidate("receipt"))
        let restored = PhotoUtilityCache(url: url)
        #expect(restored.result(for: photo) == false)
        #expect(restored.result(for: candidate("receipt")) == true)
        #expect(restored.result(for: candidate("photo", modified: Date(timeIntervalSince1970: 1))) == nil)
        #expect(restored.result(for: candidate("unclassified")) == nil)
    }

    @Test func utilityCacheBoundsStorageAndToleratesCorruptFile() throws {
        let directory = temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("classifications.json")
        var cache = PhotoUtilityCache(url: url, capacity: 2)
        for i in 0..<3 { cache.record(false, for: candidate("photo-\(i)")) }
        #expect(cache.entries.count == 2)
        #expect(PhotoUtilityCache(url: url, capacity: 2).entries.count == 2)
        try Data("invalid json".utf8).write(to: url)
        #expect(PhotoUtilityCache(url: url).entries.isEmpty)
    }
}

private func candidate(_ identifier: String, orientation: WallpaperOrientation = .landscape,
                       screenshot: Bool = false, modified: Date? = nil) -> WallpaperPhotoCandidate {
    WallpaperPhotoCandidate(identifier: identifier, modificationDate: modified,
                            orientation: orientation, isScreenshot: screenshot)
}

private actor FakeWallpaperCandidateSource: WallpaperCandidateProviding {
    var photos: [WallpaperPhotoCandidate]
    let utility: Set<String>
    var failures: Set<String>
    let blocked: String?
    private var hidden: Set<String> = []
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var classifications: [String] = []

    init(photos: [WallpaperPhotoCandidate], utility: Set<String> = [], failures: Set<String> = [], blocked: String? = nil) {
        self.photos = photos
        self.utility = utility
        self.failures = failures
        self.blocked = blocked
    }
    func candidates(limit: Int, excluding: Set<String>) -> [WallpaperPhotoCandidate] {
        Array(photos.filter { !excluding.contains($0.identifier) }.prefix(limit))
    }
    func currentCandidates(_ candidates: [WallpaperPhotoCandidate]) -> [WallpaperPhotoCandidate] {
        candidates.filter { !hidden.contains($0.identifier) }
    }
    func isUtility(_ candidate: WallpaperPhotoCandidate) async -> Bool? {
        classifications.append(candidate.identifier)
        if candidate.identifier == blocked, !released { await withCheckedContinuation { gate = $0 } }
        return failures.contains(candidate.identifier) ? nil : utility.contains(candidate.identifier)
    }
    func hide(_ identifiers: Set<String>) { hidden = identifiers }
    func edit(_ candidate: WallpaperPhotoCandidate) {
        photos = photos.map { $0.identifier == candidate.identifier ? candidate : $0 }
        failures.remove(candidate.identifier)
    }
    func release() { released = true; gate?.resume(); gate = nil }
    func waitForCalls(atLeast count: Int) async {
        for _ in 0..<100 {
            if classifications.count >= count { return }
            await Task.yield()
        }
    }
}
