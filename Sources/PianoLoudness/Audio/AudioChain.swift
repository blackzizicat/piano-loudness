import Foundation

struct ProcessingReport {
    var inputLUFS: Double?
    var outputLUFS: Double?
    var inputPeakDB: Double
    var outputPeakDB: Double
    var maxCompressionDB: Double
    var makeupDB: Double
}

/// input gain -> compressor -> loudness-targeted makeup gain -> limiter.
enum AudioChain {
    static func process(_ input: StereoBuffer, settings: EffectSettings) -> (StereoBuffer, ProcessingReport) {
        var work = input
        work.applyGain(db: settings.inputGainDB)
        let reduction = Compressor.process(&work, settings: settings.compressor)

        var output = work
        var makeup = 0.0

        if settings.normalize.isEnabled, let current = LoudnessMeter.integratedLUFS(work) {
            let target = settings.normalize.targetLUFS
            makeup = min(max(target - current, -20), 40)
            // The limiter lowers loudness slightly, so iterate on the measured result.
            for attempt in 0..<4 {
                output = render(work, makeupDB: makeup, settings: settings)
                guard let measured = LoudnessMeter.integratedLUFS(output), attempt < 3 else { break }
                let error = target - measured
                if abs(error) < 0.2 { break }
                makeup += error
            }
        } else {
            output = render(work, makeupDB: 0, settings: settings)
        }

        for i in 0..<output.count {
            output.left[i] = min(max(output.left[i], -1), 1)
            output.right[i] = min(max(output.right[i], -1), 1)
        }

        let report = ProcessingReport(
            inputLUFS: LoudnessMeter.integratedLUFS(input),
            outputLUFS: LoudnessMeter.integratedLUFS(output),
            inputPeakDB: linearToDB(Double(input.peak)),
            outputPeakDB: linearToDB(Double(output.peak)),
            maxCompressionDB: reduction,
            makeupDB: makeup
        )
        return (output, report)
    }

    private static func render(_ buffer: StereoBuffer, makeupDB: Double, settings: EffectSettings) -> StereoBuffer {
        var out = buffer
        out.applyGain(db: makeupDB)
        Limiter.process(&out, settings: settings.limiter)
        return out
    }
}
