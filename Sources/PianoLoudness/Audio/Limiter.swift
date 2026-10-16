import Foundation

/// Offline look-ahead peak limiter.
///
/// Required gain per sample -> trailing minimum over the look-ahead window ->
/// look-ahead moving average (gain is already lowered before the peak) ->
/// release smoothing that never exceeds the required gain.
enum Limiter {
    static func process(_ buffer: inout StereoBuffer, settings s: LimiterSettings) {
        let n = buffer.count
        guard s.isEnabled, n > 0 else { return }

        let sr = buffer.sampleRate
        let ceiling = Float(dbToLinear(s.ceilingDB))
        let look = max(1, Int(s.lookaheadMs * 0.001 * sr))

        var left = buffer.left
        var right = buffer.right

        var required = [Float](repeating: 1, count: n)
        for i in 0..<n {
            let p = max(abs(left[i]), abs(right[i]))
            if p > ceiling { required[i] = ceiling / p }
        }

        // Trailing minimum with a monotonic deque.
        var minimum = [Float](repeating: 1, count: n)
        var deque = [Int](repeating: 0, count: n)
        var head = 0
        var tail = 0
        for j in 0..<n {
            while tail > head && required[deque[tail - 1]] >= required[j] { tail -= 1 }
            deque[tail] = j
            tail += 1
            if deque[head] <= j - look { head += 1 }
            minimum[j] = required[deque[head]]
        }

        // Look-ahead moving average over minimum[i ..< i + look].
        var smoothed = [Float](repeating: 1, count: n)
        var sum = 0.0
        for k in 0..<look { sum += Double(minimum[min(k, n - 1)]) }
        for i in 0..<n {
            smoothed[i] = Float(sum / Double(look))
            sum -= Double(minimum[min(i, n - 1)])
            sum += Double(minimum[min(i + look, n - 1)])
        }

        let rel = Float(exp(-1.0 / (max(s.releaseMs, 1) * 0.001 * sr)))
        var previous: Float = 1
        for i in 0..<n {
            var g = smoothed[i]
            if g > previous { g = rel * previous + (1 - rel) * g }
            previous = g
            left[i] = min(max(left[i] * g, -ceiling), ceiling)
            right[i] = min(max(right[i] * g, -ceiling), ceiling)
        }

        buffer.left = left
        buffer.right = right
    }
}
