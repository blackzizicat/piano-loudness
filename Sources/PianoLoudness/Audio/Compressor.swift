import Foundation

/// Feed-forward stereo-linked compressor with a soft knee.
enum Compressor {
    /// Returns the maximum gain reduction in dB (positive number).
    @discardableResult
    static func process(_ buffer: inout StereoBuffer, settings s: CompressorSettings) -> Double {
        let n = buffer.count
        guard s.isEnabled, n > 0 else { return 0 }

        let sr = buffer.sampleRate
        let attack = exp(-1.0 / (max(s.attackMs, 0.01) * 0.001 * sr))
        let release = exp(-1.0 / (max(s.releaseMs, 0.01) * 0.001 * sr))
        let ratio = max(s.ratio, 1)
        let knee = max(s.kneeDB, 0)

        var left = buffer.left
        var right = buffer.right
        var state = 0.0
        var maxReduction = 0.0

        for i in 0..<n {
            let l = left[i]
            let r = right[i]
            let level = linearToDB(Double(max(abs(l), abs(r))))
            let over = level - s.thresholdDB

            var reduction = 0.0
            if 2 * over < -knee {
                reduction = 0
            } else if knee > 0 && 2 * abs(over) <= knee {
                let x = over + knee / 2
                reduction = (1 / ratio - 1) * x * x / (2 * knee)
            } else {
                reduction = (1 / ratio - 1) * over
            }

            let coeff = reduction < state ? attack : release
            state = coeff * state + (1 - coeff) * reduction
            maxReduction = max(maxReduction, -state)

            let g = Float(dbToLinear(state))
            left[i] = l * g
            right[i] = r * g
        }

        buffer.left = left
        buffer.right = right
        return maxReduction
    }
}
