import AVFoundation

enum ExportError: LocalizedError {
    case noAudioTrack
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "The video has no audio track."
        case .noVideoTrack: return "The video has no video track."
        case .readerFailed(let m): return "Could not read audio: \(m)"
        case .writerFailed(let m): return "Could not write audio: \(m)"
        case .exportFailed(let m): return "Export failed: \(m)"
        }
    }
}

/// Decodes the audio track, runs the effect chain, and remuxes the result with the
/// original video track without re-encoding the video.
enum VideoExporter {
    static let sampleRate: Double = 48_000

    static func run(
        source: URL,
        settings: EffectSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, ProcessingReport) {
        let asset = AVURLAsset(url: source)

        progress(0.05)
        let (decoded, audioStart) = try await readAudio(from: asset)
        progress(0.35)

        let (processed, report) = AudioChain.process(decoded, settings: settings)
        progress(0.55)

        let tempAudio = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-\(UUID().uuidString).m4a")
        try writeAudio(processed, to: tempAudio)
        progress(0.7)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("piano-loudness-\(UUID().uuidString).mov")
        try await remux(video: asset, processedAudio: tempAudio, audioStart: audioStart, to: output)
        try? FileManager.default.removeItem(at: tempAudio)
        progress(1)

        return (output, report)
    }

    static func readAudio(from asset: AVAsset) async throws -> (StereoBuffer, CMTime) {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }
        let trackRange = try await track.load(.timeRange)
        let duration = try await asset.load(.duration)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
        ])
        guard reader.canAdd(output) else { throw ExportError.readerFailed("cannot add output") }
        reader.add(output)
        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        let estimated = Int(max(duration.seconds, 0) * sampleRate)
        var left = [Float]()
        var right = [Float]()
        left.reserveCapacity(estimated)
        right.reserveCapacity(estimated)

        let frameSize = MemoryLayout<Float>.size * 2
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let frames = CMBlockBufferGetDataLength(block) / frameSize
            if frames == 0 { continue }
            var interleaved = [Float](repeating: 0, count: frames * 2)
            let status = interleaved.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: frames * frameSize,
                    destination: raw.baseAddress!
                )
            }
            guard status == kCMBlockBufferNoErr else {
                throw ExportError.readerFailed("copy failed (\(status))")
            }
            for i in 0..<frames {
                left.append(interleaved[2 * i])
                right.append(interleaved[2 * i + 1])
            }
        }
        if reader.status == .failed {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        return (StereoBuffer(left: left, right: right, sampleRate: sampleRate), trackRange.start)
    }

    static func writeAudio(_ buffer: StereoBuffer, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: buffer.sampleRate,
            channels: 2, interleaved: false
        ) else { throw ExportError.writerFailed("invalid format") }

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: buffer.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 256_000,
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let chunk = 32_768
            var offset = 0
            while offset < buffer.count {
                let count = min(chunk, buffer.count - offset)
                guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channels = pcm.floatChannelData
                else { throw ExportError.writerFailed("buffer allocation failed") }
                pcm.frameLength = AVAudioFrameCount(count)
                buffer.left.withUnsafeBufferPointer {
                    channels[0].update(from: $0.baseAddress! + offset, count: count)
                }
                buffer.right.withUnsafeBufferPointer {
                    channels[1].update(from: $0.baseAddress! + offset, count: count)
                }
                try file.write(from: pcm)
                offset += count
            }
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.writerFailed(error.localizedDescription)
        }
    }

    static func remux(video asset: AVURLAsset, processedAudio: URL, audioStart: CMTime, to output: URL) async throws {
        let composition = AVMutableComposition()

        guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first,
              let dstVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noVideoTrack }

        let duration = try await asset.load(.duration)
        try dstVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcVideo, at: .zero)
        dstVideo.preferredTransform = try await srcVideo.load(.preferredTransform)

        let audioAsset = AVURLAsset(url: processedAudio)
        guard let srcAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let dstAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noAudioTrack }
        let audioDuration = try await srcAudio.load(.timeRange).duration
        let remaining = CMTimeSubtract(duration, audioStart)
        let insertDuration = CMTimeMinimum(audioDuration, remaining)
        try dstAudio.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: srcAudio, at: audioStart)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.exportFailed("cannot create export session")
        }
        try? FileManager.default.removeItem(at: output)

        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: output, as: .mov)
            } catch {
                throw ExportError.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = output
            session.outputFileType = .mov
            await session.export()
            if session.status != .completed {
                throw ExportError.exportFailed(session.error?.localizedDescription ?? "unknown")
            }
        }
    }
}
