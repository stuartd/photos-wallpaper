import AppKit
import Combine
import Photos
import SwiftUI

enum PhotoHistoryIdentifier {
    static let maxPasteCharacterCount = 20_000
    static let maxIdentifierCount = 25
    static let exampleHistoryLine = WallpaperHistoryEntryFormatter.exampleLine
    private static let currentHistoryLineRegex = try! NSRegularExpression(
        pattern: #"^\s*Photo ID\s+(\S+)\s+was set as the wallpaper\b"#
    )

    struct ExtractionResult: Equatable {
        let identifiers: [String]
        let isPasteTooLarge: Bool
        let didReachIdentifierLimit: Bool
    }

    static func extract(from pastedText: String) -> String? {
        extractIdentifiers(from: pastedText).identifiers.first
    }

    static func extractIdentifiers(from pastedText: String,
                                   maxCharacterCount: Int = maxPasteCharacterCount,
                                   maxIdentifierCount: Int = maxIdentifierCount) -> ExtractionResult {
        let trimmedText = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return ExtractionResult(identifiers: [], isPasteTooLarge: false, didReachIdentifierLimit: false)
        }
        guard trimmedText.count <= maxCharacterCount else {
            return ExtractionResult(identifiers: [], isPasteTooLarge: true, didReachIdentifierLimit: false)
        }

        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()
        for line in trimmedText.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let identifier = identifier(in: String(line)) ?? normalizedRawIdentifier(String(line)) else { continue }
            guard !seenIdentifiers.contains(identifier) else { continue }
            identifiers.append(identifier)
            seenIdentifiers.insert(identifier)
            if identifiers.count == maxIdentifierCount {
                return ExtractionResult(identifiers: identifiers, isPasteTooLarge: false, didReachIdentifierLimit: true)
            }
        }

        return ExtractionResult(identifiers: identifiers, isPasteTooLarge: false, didReachIdentifierLimit: false)
    }

    private static func identifier(in line: String) -> String? {
        let matchRange = NSRange(line.startIndex..., in: line)
        guard let match = currentHistoryLineRegex.firstMatch(in: line, range: matchRange),
              let identifierRange = Range(match.range(at: 1), in: line) else { return nil }
        return normalizedIdentifier(String(line[identifierRange]))
    }

    private static func normalizedIdentifier(_ identifier: String) -> String? {
        let trimmedIdentifier = identifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ")")))
        return trimmedIdentifier.isEmpty ? nil : trimmedIdentifier
    }

    private static func normalizedRawIdentifier(_ identifier: String) -> String? {
        guard let trimmedIdentifier = normalizedIdentifier(identifier) else { return nil }
        guard trimmedIdentifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        guard trimmedIdentifier.contains("/") else { return nil }
        return trimmedIdentifier
    }
}

enum CurrentWallpaperAlbumAdditionResult: Equatable {
    case added(addedCount: Int, missingIdentifierCount: Int, failedAddCount: Int)
    case noRememberedWallpapers
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

struct CurrentWallpaperAlbumAdder {
    let photoManager: PhotoManaging

    func addWallpapers(withLocalIdentifiers identifiers: [String],
                       completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        let identifiers = deduplicatedIdentifiers(identifiers)
        guard !identifiers.isEmpty else {
            completion(.noRememberedWallpapers)
            return
        }

        switch photoManager.findPhotos(localIdentifiers: identifiers) {
        case .photos(let assets, let missingIdentifierCount):
            addAssetsToAlbum(assets,
                             missingIdentifierCount: missingIdentifierCount,
                             completion: completion)
        case .waitingForAuthorization:
            completion(.waitingForAuthorization)
        case .permissionDenied:
            completion(.permissionDenied)
        case .unavailable:
            completion(.unavailable)
        }
    }

    private func deduplicatedIdentifiers(_ identifiers: [String]) -> [String] {
        var seenIdentifiers = Set<String>()
        var deduplicatedIdentifiers: [String] = []
        for identifier in identifiers {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentifier.isEmpty, !seenIdentifiers.contains(trimmedIdentifier) else { continue }
            deduplicatedIdentifiers.append(trimmedIdentifier)
            seenIdentifiers.insert(trimmedIdentifier)
        }
        return deduplicatedIdentifiers
    }

    private func addAssetsToAlbum(_ assets: [PHAsset],
                                  missingIdentifierCount: Int,
                                  completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        guard !assets.isEmpty else {
            completion(.added(addedCount: 0,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: 0))
            return
        }

        addAssetToAlbum(assets,
                        index: 0,
                        missingIdentifierCount: missingIdentifierCount,
                        failedAddCount: 0,
                        completion: completion)
    }

    private func addAssetToAlbum(_ assets: [PHAsset],
                                 index: Int,
                                 missingIdentifierCount: Int,
                                 failedAddCount: Int,
                                 completion: @escaping (CurrentWallpaperAlbumAdditionResult) -> Void) {
        guard index < assets.count else {
            completion(.added(addedCount: assets.count - failedAddCount,
                              missingIdentifierCount: missingIdentifierCount,
                              failedAddCount: failedAddCount))
            return
        }

        photoManager.addToPhotosWallpaperAlbum(asset: assets[index]) { result in
            let nextFailedAddCount: Int
            switch result {
            case .success:
                nextFailedAddCount = failedAddCount
            case .failure(let error):
                debugLog("CurrentWallpaperAlbumAdder: failed to add current wallpaper \(index + 1) to album: \(error)")
                nextFailedAddCount = failedAddCount + 1
            }
            addAssetToAlbum(assets,
                            index: index + 1,
                            missingIdentifierCount: missingIdentifierCount,
                            failedAddCount: nextFailedAddCount,
                            completion: completion)
        }
    }
}

final class CurrentWallpaperAlbumController {
    private let historyLogger: WallpaperHistoryLogger
    private let photoManager: PhotoManaging
    private let notifier: WallpaperCycleNotifying

    init(historyLogger: WallpaperHistoryLogger,
         photoManager: PhotoManaging = PhotoManager.shared,
         notifier: WallpaperCycleNotifying = UserNotificationWallpaperCycleNotifier()) {
        self.historyLogger = historyLogger
        self.photoManager = photoManager
        self.notifier = notifier
    }

    func addCurrentWallpapersToAlbum() {
        let identifiers = historyLogger.currentWallpaperIdentifiersSnapshot()
        CurrentWallpaperAlbumAdder(photoManager: photoManager).addWallpapers(withLocalIdentifiers: identifiers) { [weak self] result in
            DispatchQueue.main.async {
                self?.handle(result)
            }
        }
    }

    private func handle(_ result: CurrentWallpaperAlbumAdditionResult) {
        switch result {
        case .added(let addedCount, let missingIdentifierCount, let failedAddCount):
            if addedCount > 0, missingIdentifierCount == 0, failedAddCount == 0 {
                notifier.notifyCurrentWallpapersAddedToAlbum(count: addedCount)
                return
            }
            showAlert(title: "Some Wallpapers Could Not Be Added",
                      message: albumSummary(addedCount: addedCount,
                                            missingIdentifierCount: missingIdentifierCount,
                                            failedAddCount: failedAddCount))
        case .noRememberedWallpapers:
            showAlert(title: "No Current Wallpapers Yet",
                      message: "Photos Wallpaper can add current wallpapers after it has set them at least once.")
        case .waitingForAuthorization:
            showAlert(title: "Photos Access Needed",
                      message: "Photos Wallpaper is waiting for permission to read your Photos library. Try again after approving access.")
        case .permissionDenied:
            showAlert(title: "Photos Access Needed",
                      message: "Enable Photos access in System Settings > Privacy & Security > Photos, then try again.")
        case .unavailable:
            showAlert(title: "Photos Unavailable",
                      message: "Photos Wallpaper could not search your Photos library right now.")
        }
    }

    private func albumSummary(addedCount: Int, missingIdentifierCount: Int, failedAddCount: Int) -> String {
        var parts: [String] = []
        parts.append("Added \(addedCount) wallpaper photo\(addedCount == 1 ? "" : "s") to the Photos Wallpaper album.")
        if missingIdentifierCount > 0 {
            parts.append("\(missingIdentifierCount) remembered wallpaper photo\(missingIdentifierCount == 1 ? "" : "s") could not be found in Photos.")
        }
        if failedAddCount > 0 {
            parts.append("\(failedAddCount) wallpaper photo\(failedAddCount == 1 ? "" : "s") could not be added.")
        }
        return parts.joined(separator: " ")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum PhotoHistoryPhotoFindingResult {
    case photos([PHAsset], missingIdentifierCount: Int, didReachIdentifierLimit: Bool)
    case waitingForAuthorization
    case permissionDenied
    case unavailable
}

struct PhotoHistoryPhotoFinder {
    let photoManager: PhotoManaging

    func findPhotos(for extractionResult: PhotoHistoryIdentifier.ExtractionResult) -> PhotoHistoryPhotoFindingResult {
        switch photoManager.findPhotos(localIdentifiers: extractionResult.identifiers) {
        case .photos(let assets, let missingIdentifierCount):
            return .photos(assets,
                           missingIdentifierCount: missingIdentifierCount,
                           didReachIdentifierLimit: extractionResult.didReachIdentifierLimit)
        case .waitingForAuthorization:
            return .waitingForAuthorization
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        }
    }
}

final class PhotoHistoryLookupWindowController {
    private let photoManager: PhotoManaging
    private var window: NSWindow?

    init(photoManager: PhotoManaging = PhotoManager.shared) {
        self.photoManager = photoManager
    }

    func showLookup() {
        guard let extractionResult = promptForHistoryIdentifiers() else { return }
        findPhotos(for: extractionResult)
    }

    private func promptForHistoryIdentifiers() -> PhotoHistoryIdentifier.ExtractionResult? {
        let alert = NSAlert()
        alert.messageText = "Find Photos from Wallpaper History"
        alert.informativeText = "Paste one or more whole lines from wallpaper history. If you know exactly what to copy from a line, that works too."
        alert.addButton(withTitle: "Find")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 96))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let input = NSTextView(frame: scrollView.bounds)
        input.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.string = ""
        scrollView.documentView = input
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let extractionResult = PhotoHistoryIdentifier.extractIdentifiers(from: input.string)
        if extractionResult.isPasteTooLarge {
            showAlert(title: "Paste Too Large",
                      message: "Paste up to \(PhotoHistoryIdentifier.maxPasteCharacterCount) characters of wallpaper history at a time.")
            return nil
        }
        guard !extractionResult.identifiers.isEmpty else {
            showAlert(title: "No History Lines Found",
                      message: "Paste the whole wallpaper history line that contains the photo you want, for example:\n\n\(PhotoHistoryIdentifier.exampleHistoryLine)")
            return nil
        }
        return extractionResult
    }

    private func findPhotos(for extractionResult: PhotoHistoryIdentifier.ExtractionResult) {
        let lookupResult = PhotoHistoryPhotoFinder(photoManager: photoManager).findPhotos(for: extractionResult)
        let assets: [PHAsset]
        let missingIdentifierCount: Int
        let didReachIdentifierLimit: Bool

        switch lookupResult {
        case .photos(let foundAssets, let notFoundCount, let reachedLimit):
            assets = foundAssets
            missingIdentifierCount = notFoundCount
            didReachIdentifierLimit = reachedLimit
        case .waitingForAuthorization:
            showAlert(title: "Photos Access Needed",
                      message: "Photos Wallpaper is waiting for permission to read your Photos library. Try again after approving access.")
            return
        case .permissionDenied:
            showAlert(title: "Photos Access Needed",
                      message: "Enable Photos access in System Settings > Privacy & Security > Photos, then try again.")
            return
        case .unavailable:
            showAlert(title: "Photos Unavailable",
                      message: "Photos Wallpaper could not search your Photos library right now.")
            return
        }

        guard !assets.isEmpty else {
            showAlert(title: "Photos Not Found",
                      message: "Photos Wallpaper could not find photos for those wallpaper history entries in the current Photos library.")
            return
        }

        showPreview(for: assets,
                    missingIdentifierCount: missingIdentifierCount,
                    didReachIdentifierLimit: didReachIdentifierLimit)
    }

    private func showPreview(for assets: [PHAsset], missingIdentifierCount: Int, didReachIdentifierLimit: Bool) {
        let viewModel = PhotoHistoryLookupViewModel(assets: assets,
                                                    missingIdentifierCount: missingIdentifierCount,
                                                    didReachIdentifierLimit: didReachIdentifierLimit,
                                                    photoManager: photoManager)
        let view = PhotoHistoryLookupView(viewModel: viewModel) { [weak self] in
            self?.window?.close()
        }
        let hostingController = NSHostingController(rootView: view)
        let previewWindow = NSWindow(contentViewController: hostingController)
        previewWindow.title = "Find Photos from Wallpaper History"
        previewWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        previewWindow.setContentSize(NSSize(width: 560, height: 560))
        previewWindow.center()
        previewWindow.isReleasedWhenClosed = false
        previewWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        window = previewWindow
        viewModel.loadPreview()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class PhotoHistoryLookupViewModel: ObservableObject {
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isAddingToAlbum = false
    @Published private(set) var didAddToAlbum = false

    let assets: [PHAsset]
    let displayNames: [String]
    let missingIdentifierCount: Int
    let didReachIdentifierLimit: Bool
    private let photoManager: PhotoManaging

    var title: String {
        assets.count == 1 ? displayNames[0] : "\(assets.count) Photos Found"
    }

    var summary: String {
        var parts = ["\(assets.count) photo\(assets.count == 1 ? "" : "s") ready to add."]
        if missingIdentifierCount > 0 {
            parts.append("\(missingIdentifierCount) history entr\(missingIdentifierCount == 1 ? "y" : "ies") could not be found.")
        }
        if didReachIdentifierLimit {
            parts.append("Only the first \(PhotoHistoryIdentifier.maxIdentifierCount) matching entries were processed.")
        }
        return parts.joined(separator: " ")
    }

    init(assets: [PHAsset],
         missingIdentifierCount: Int,
         didReachIdentifierLimit: Bool,
         photoManager: PhotoManaging) {
        self.assets = assets
        self.photoManager = photoManager
        self.displayNames = assets.map { photoManager.displayName(for: $0) }
        self.missingIdentifierCount = missingIdentifierCount
        self.didReachIdentifierLimit = didReachIdentifierLimit
    }

    func loadPreview() {
        guard let asset = assets.first else { return }
        let targetSize = CGSize(width: 900, height: 700)
        photoManager.requestImage(for: asset, targetSize: targetSize) { [weak self] image in
            DispatchQueue.main.async {
                if let image {
                    self?.previewImage = image
                    self?.statusMessage = nil
                } else {
                    self?.statusMessage = "Photos Wallpaper could not load a preview for this photo."
                }
            }
        }
    }

    func addToAlbum() {
        guard !isAddingToAlbum else { return }
        isAddingToAlbum = true
        statusMessage = nil

        addAssetToAlbum(at: 0, failedCount: 0)
    }

    private func addAssetToAlbum(at index: Int, failedCount: Int) {
        guard index < assets.count else {
            DispatchQueue.main.async {
                self.isAddingToAlbum = false
                self.didAddToAlbum = failedCount == 0
                if failedCount == 0 {
                    self.statusMessage = "Added \(self.assets.count) photo\(self.assets.count == 1 ? "" : "s") to the Photos Wallpaper album."
                } else {
                    let addedCount = self.assets.count - failedCount
                    self.statusMessage = "Added \(addedCount) photo\(addedCount == 1 ? "" : "s"). \(failedCount) photo\(failedCount == 1 ? "" : "s") could not be added."
                }
            }
            return
        }

        photoManager.addToPhotosWallpaperAlbum(asset: assets[index]) { [weak self] result in
            guard let self else { return }
            let nextFailedCount: Int
            switch result {
            case .success:
                nextFailedCount = failedCount
            case .failure(let error):
                debugLog("PhotoHistoryLookupViewModel: failed to add photo \(index + 1) to album: \(error)")
                nextFailedCount = failedCount + 1
            }
            DispatchQueue.main.async {
                self.addAssetToAlbum(at: index + 1, failedCount: nextFailedCount)
            }
        }
    }
}

struct PhotoHistoryLookupView: View {
    @ObservedObject var viewModel: PhotoHistoryLookupViewModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let previewImage = viewModel.previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(viewModel.title)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)

            Text(viewModel.summary)
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .textSelection(.enabled)

            if viewModel.displayNames.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.displayNames.enumerated()), id: \.offset) { _, displayName in
                            Text(displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 86)
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(viewModel.didAddToAlbum ? Color.secondary : Color.red)
            }

            HStack {
                Spacer()
                Button("Close") {
                    close()
                }

                Button {
                    viewModel.addToAlbum()
                } label: {
                    if viewModel.isAddingToAlbum {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.didAddToAlbum ? "Added to Album" : "Add to Photos Wallpaper Album")
                    }
                }
                .disabled(viewModel.isAddingToAlbum || viewModel.didAddToAlbum)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 480)
    }
}
