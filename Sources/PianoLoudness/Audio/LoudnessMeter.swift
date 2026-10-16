import Foundation

/// Integrated loudness per ITU-R BS.1770-4 (K-weighting, 400 ms blocks,
/// 75% overlap, absolute gate -70 LUFS, relative gate -10 LU).
enum LoudnessMeter {
    private struct Biquad {
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0
        var z2 = 0.0

        init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
            self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private static func kWeighting(sampleRate fs: Double) -> [Biquad] {
        // Stage 1: high shelf.
        let f1 = 1681.974450955533
        let g1 = 3.999843853973347
        let q1 = 0.7071752369554196
        let k1 = tan(Double.pi * f1 / fs)
        let vh = pow(10, g1 / 20)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k1 / q1 + k1 * k1
        let shelf = Biquad(
            b0: (vh + vb * k1 / q1 + k1 * k1) / a0,
            b1: 2 * (k1 * k1 - vh) / a0,
            b2: (vh - vb * k1 / q1 + k1 * k1) / a0,
            a1: 2 * (k1 * k1 - 1) / a0,
            a2: (1 - k1 / q1 + k1 * k1) / a0
        )

        // Stage 2: high-pass (RLB).
        let f2 = 38.13547087602444
        let q2 = 0.5003270373238773
        let k2 = tan(Double.pi * f2 / fs)
        let c0 = 1 + k2 / q2 + k2 * k2
        let highpass = Biquad(
            b0: 1, b1: -2, b2: 1,
            a1: 2 * (k2 * k2 - 1) / c0,
            a2: (1 - k2 / q2 + k2 * k2) / c0
        )
        return [shelf, highpass]
    }

    private static func loudness(of energy: Double) -> Double {
        -0.691 + 10 * log10(max(energy, 1e-12))
    }

    /// Returns nil when the signal is empty or entirely below the absolute gate.
    static func integratedLUFS(_ buffer: StereoBuffer) -> Double? {
        let n = buffer.count
        guard n > 0 else { return nil }

        let hop = max(1, Int(0.1 * buffer.sampleRate))
        var filtersL = kWeighting(sampleRate: buffer.sampleRate)
        var filtersR = filtersL

        var segments = [Double](repeating: 0, count: (n + hop - 1) / hop)
        for i in 0..<n {
            var l = Double(buffer.left[i])
            var r = Double(buffer.right[i])
            for s in 0..<filtersL.count {
                l = filtersL[s].process(l)
                r = filtersR[s].process(r)
            }
            segments[i / hop] += l * l + r * r
        }

        let fullSegments = n / hop
        guard fullSegments >= 4 else {
            let total = segments.reduce(0, +) / Double(n)
            return total > 0 ? loudness(of: total) : nil
        }

        var blocks: [Double] = []
        for i in 0...(fullSegments - 4) {
            let e = (segments[i] + segments[i + 1] + segments[i + 2] + segments[i + 3]) / Double(4 * hop)
            blocks.append(e)
        }

        let absolute = blocks.filter { loudness(of: $0) > -70 }
        guard !absolute.isEmpty else { return nil }

        let relativeThreshold = loudness(of: absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { loudness(of: $0) > relativeThreshold }
        guard !gated.isEmpty else { return nil }
        return loudness(of: gated.reduce(0, +) / Double(gated.count))
    }
}
