import AVFoundation
import Photos
import PhotosUI
import SwiftUI

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("input-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var pickerItem: PhotosPickerItem?
    @Published var preset: Preset = .natural
    @Published var settings = Preset.natural.settings
    @Published var showProcessed = false
    @Published private(set) var sourceURL: URL?
    @Published private(set) var resultURL: URL?
    @Published private(set) var report: ProcessingReport?
    @Published private(set) var progress = 0.0
    @Published private(set) var isBusy = false
    @Published private(set) var player: AVPlayer?
    @Published var message: String?

    func loadPicked() async {
        guard let item = pickerItem else { return }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            sourceURL = movie.url
            resultURL = nil
            report = nil
            showProcessed = false
            message = nil
            updatePlayer()
        } catch {
            message = error.localizedDescription
        }
    }

    func applyPreset() {
        settings = preset.settings
    }

    func updatePlayer() {
        let url = (showProcessed ? resultURL : nil) ?? sourceURL
        guard let url else {
            player = nil
            return
        }
        player?.pause()
        player = AVPlayer(url: url)
    }

    func process() {
        guard let sourceURL, !isBusy else { return }
        isBusy = true
        progress = 0
        message = nil
        let settings = settings

        Task {
            do {
                let (url, report) = try await VideoExporter.run(source: sourceURL, settings: settings) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                resultURL = url
                self.report = report
                showProcessed = true
                updatePlayer()
            } catch {
                message = error.localizedDescription
            }
            isBusy = false
        }
    }

    func saveToPhotos() async {
        guard let url = resultURL else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = "Photos access was denied."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            message = "Saved to Photos."
        } catch {
            message = error.localizedDescription
        }
    }
}
