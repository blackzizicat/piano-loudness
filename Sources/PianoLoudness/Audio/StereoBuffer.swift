import Foundation

struct StereoBuffer {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double

    var count: Int { left.count }

    var peak: Float {
        var p: Float = 0
        for i in 0..<count { p = max(p, abs(left[i]), abs(right[i])) }
        return p
    }

    mutating func applyGain(db: Double) {
        let g = Float(dbToLinear(db))
        for i in 0..<count {
            left[i] *= g
            right[i] *= g
        }
    }
}
