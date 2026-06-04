import AppKit
import Combine
import Photos
import SwiftUI

enum PhotoHistoryIdentifier {
    static func extract(from pastedText: String) -> String? {
        let trimmedText = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        if let markerRange = trimmedText.range(of: "id:") {
            let identifierStart = markerRange.upperBound
            let remainder = trimmedText[identifierStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let closingParenthesis = remainder.firstIndex(of: ")") {
                return normalizedIdentifier(String(remainder[..<closingParenthesis]))
            }
            return normalizedIdentifier(remainder)
        }

        return normalizedIdentifier(trimmedText)
    }

    private static func normalizedIdentifier(_ identifier: String) -> String? {
        let trimmedIdentifier = identifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ")")))
        return trimmedIdentifier.isEmpty ? nil : trimmedIdentifier
    }
}

final class PhotoHistoryLookupWindowController {
    private let photoManager: PhotoManager
    private var window: NSWindow?

    init(photoManager: PhotoManager = .shared) {
        self.photoManager = photoManager
    }

    func showLookup() {
        guard let identifier = promptForHistoryIdentifier() else { return }

        switch photoManager.findPhoto(localIdentifier: identifier) {
        case .photo(let asset):
            showPreview(for: asset)
        case .waitingForAuthorization:
            showAlert(title: "Photos Access Needed",
                      message: "Photos Wallpaper is waiting for permission to read your Photos library. Try again after approving access.")
        case .permissionDenied:
            showAlert(title: "Photos Access Needed",
                      message: "Enable Photos access in System Settings > Privacy & Security > Photos, then try again.")
        case .notFound:
            showAlert(title: "Photo Not Found",
                      message: "Photos Wallpaper could not find a photo for that history ID in the current Photos library.")
        case .unavailable:
            showAlert(title: "Photos Unavailable",
                      message: "Photos Wallpaper could not search your Photos library right now.")
        }
    }

    private func promptForHistoryIdentifier() -> String? {
        let alert = NSAlert()
        alert.messageText = "Find Photo from History Line"
        alert.informativeText = "Paste the whole line from wallpaper history that contains the photo you want. Pasting just the Photos asset ID also works."
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
        guard let identifier = PhotoHistoryIdentifier.extract(from: input.string) else {
            showAlert(title: "No History Line", message: "Paste the whole wallpaper history line that contains the photo you want.")
            return nil
        }
        return identifier
    }

    private func showPreview(for asset: PHAsset) {
        let viewModel = PhotoHistoryLookupViewModel(asset: asset, photoManager: photoManager)
        let view = PhotoHistoryLookupView(viewModel: viewModel) { [weak self] in
            self?.window?.close()
        }
        let hostingController = NSHostingController(rootView: view)
        let previewWindow = NSWindow(contentViewController: hostingController)
        previewWindow.title = "Find Photo from History Line"
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

    let asset: PHAsset
    let displayName: String
    private let photoManager: PhotoManager

    init(asset: PHAsset, photoManager: PhotoManager) {
        self.asset = asset
        self.photoManager = photoManager
        self.displayName = photoManager.displayName(for: asset)
    }

    func loadPreview() {
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

        photoManager.addToPhotosWallpaperAlbum(asset: asset) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAddingToAlbum = false
                switch result {
                case .success:
                    self?.didAddToAlbum = true
                    self?.statusMessage = "Added to the Photos Wallpaper album."
                case .failure(let error):
                    self?.statusMessage = error.localizedDescription
                }
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

            Text(viewModel.displayName)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)

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
