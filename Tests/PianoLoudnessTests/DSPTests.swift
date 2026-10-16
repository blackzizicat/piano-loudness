import XCTest
@testable import PianoLoudness

final class DSPTests: XCTestCase {
    private let sr = 48_000.0

    private func sine(amplitudeDB: Double, seconds: Double = 5, freq: Double = 1000) -> StereoBuffer {
        let n = Int(seconds * sr)
        let a = Float(dbToLinear(amplitudeDB))
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n { samples[i] = a * Float(sin(2 * Double.pi * freq * Double(i) / sr)) }
        return StereoBuffer(left: samples, right: samples, sampleRate: sr)
    }

    func testLoudnessOfFullScaleSine() throws {
        let lufs = try XCTUnwrap(LoudnessMeter.integratedLUFS(sine(amplitudeDB: 0)))
        XCTAssertEqual(lufs, 0, accuracy: 0.5)
    }

    func testLoudnessScalesWithGain() throws {
        let a = try XCTUnwrap(LoudnessMeter.integratedLUFS(sine(amplitudeDB: -20)))
        let b = try XCTUnwrap(LoudnessMeter.integratedLUFS(sine(amplitudeDB: -26)))
        XCTAssertEqual(a - b, 6, accuracy: 0.1)
    }

    func testLimiterRespectsCeiling() {
        var buffer = sine(amplitudeDB: 6)
        let settings = LimiterSettings(isEnabled: true, ceilingDB: -1, lookaheadMs: 5, releaseMs: 80)
        Limiter.process(&buffer, settings: settings)
        XCTAssertLessThanOrEqual(Double(buffer.peak), dbToLinear(-1) + 1e-6)
        XCTAssertGreaterThan(buffer.peak, 0.5)
    }

    func testCompressorReducesLoudSignal() {
        var buffer = sine(amplitudeDB: -6)
        let before = buffer.peak
        let reduction = Compressor.process(&buffer, settings: CompressorSettings())
        XCTAssertGreaterThan(reduction, 3)
        XCTAssertLessThan(buffer.peak, before)
    }

    func testCompressorLeavesQuietSignalAlone() {
        var buffer = sine(amplitudeDB: -50)
        let before = buffer.peak
        Compressor.process(&buffer, settings: CompressorSettings())
        XCTAssertEqual(buffer.peak, before, accuracy: before * 0.01)
    }

    func testChainReachesTargetLoudness() throws {
        let quiet = sine(amplitudeDB: -40)
        var settings = EffectSettings()
        settings.compressor.isEnabled = false
        let (out, report) = AudioChain.process(quiet, settings: settings)
        let lufs = try XCTUnwrap(LoudnessMeter.integratedLUFS(out))
        XCTAssertEqual(lufs, settings.normalize.targetLUFS, accuracy: 0.5)
        XCTAssertLessThanOrEqual(Double(out.peak), 1.0)
        XCTAssertGreaterThan(report.makeupDB, 20)
    }
}
