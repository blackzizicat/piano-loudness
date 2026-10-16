import AVFoundation
import XCTest
@testable import PianoLoudness

/// Runs the full pipeline (decode, DSP, encode, remux) on a synthetic rotated video.
final class EndToEndTests: XCTestCase {
    private let seconds = 2
    private var created: [URL] = []

    override func tearDown() {
        created.forEach { try? FileManager.default.removeItem(at: $0) }
        created = []
        super.tearDown()
    }

    private func tempURL(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString).\(ext)")
        created.append(url)
        return url
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame % 255), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }

    private func makeFixture(amplitudeDB: Double) async throws -> URL {
        let videoURL = tempURL("mov")
        try await makeVideo(at: videoURL)

        let sr = VideoExporter.sampleRate
        let n = Int(sr) * seconds
        let a = Float(dbToLinear(amplitudeDB))
        let samples = (0..<n).map { a * Float(sin(2 * Double.pi * 440 * Double($0) / sr)) }
        let audioURL = tempURL("m4a")
        try VideoExporter.writeAudio(StereoBuffer(left: samples, right: samples, sampleRate: sr), to: audioURL)

        let fixture = tempURL("mov")
        try await VideoExporter.remux(video: AVURLAsset(url: videoURL), processedAudio: audioURL, audioStart: .zero, to: fixture)
        return fixture
    }

    func testQuietVideoIsRaisedToTargetAndKeepsVideo() async throws {
        let source = try await makeFixture(amplitudeDB: -40)
        var settings = EffectSettings()
        settings.compressor.isEnabled = false

        let (output, report) = try await VideoExporter.run(source: source, settings: settings, progress: { _ in })
        created.append(output)

        XCTAssertEqual(try XCTUnwrap(report.inputLUFS), -40, accuracy: 1.5)

        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)

        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, Double(seconds), accuracy: 0.2)

        let t = try await videoTracks[0].load(.preferredTransform)
        XCTAssertEqual(t.b, 1, accuracy: 1e-3)
        XCTAssertEqual(t.c, -1, accuracy: 1e-3)

        let (decoded, _) = try await VideoExporter.readAudio(from: asset)
        let lufs = try XCTUnwrap(LoudnessMeter.integratedLUFS(decoded))
        XCTAssertEqual(lufs, settings.normalize.targetLUFS, accuracy: 1.0)
        XCTAssertLessThanOrEqual(linearToDB(Double(decoded.peak)), 0.0)
        XCTAssertEqual(Double(decoded.count) / VideoExporter.sampleRate, Double(seconds), accuracy: 0.2)
    }
}
