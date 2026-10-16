import Foundation

struct CompressorSettings: Equatable {
    var isEnabled = true
    var thresholdDB: Double = -24
    var ratio: Double = 2.5
    var attackMs: Double = 30
    var releaseMs: Double = 250
    var kneeDB: Double = 10
}

struct NormalizeSettings: Equatable {
    var isEnabled = true
    var targetLUFS: Double = -14
}

struct LimiterSettings: Equatable {
    var isEnabled = true
    var ceilingDB: Double = -1
    var lookaheadMs: Double = 5
    var releaseMs: Double = 80
}

struct EffectSettings: Equatable {
    var inputGainDB: Double = 0
    var compressor = CompressorSettings()
    var normalize = NormalizeSettings()
    var limiter = LimiterSettings()
}

enum Preset: String, CaseIterable, Identifiable {
    case natural
    case loud
    case gainOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Natural"
        case .loud: return "Loud"
        case .gainOnly: return "Gain only"
        }
    }

    var settings: EffectSettings {
        var s = EffectSettings()
        switch self {
        case .natural:
            break
        case .loud:
            s.compressor.thresholdDB = -30
            s.compressor.ratio = 4
            s.compressor.attackMs = 20
            s.compressor.releaseMs = 200
            s.normalize.targetLUFS = -12
        case .gainOnly:
            s.compressor.isEnabled = false
        }
        return s
    }
}

func dbToLinear(_ db: Double) -> Double { pow(10, db / 20) }
func linearToDB(_ x: Double) -> Double { 20 * log10(max(x, 1e-12)) }
