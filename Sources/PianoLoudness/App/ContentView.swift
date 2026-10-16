import AVKit
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var model = EditorViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PhotosPicker(selection: $model.pickerItem, matching: .videos) {
                        Label("Choose video", systemImage: "video.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let player = model.player {
                        VideoPlayer(player: player)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if model.sourceURL != nil {
                        if model.resultURL != nil {
                            Picker("Audio", selection: $model.showProcessed) {
                                Text("Original").tag(false)
                                Text("Processed").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        controls
                        processButton
                        result
                    }

                    if let message = model.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Piano Loudness")
            .onChange(of: model.pickerItem) { _, _ in Task { await model.loadPicked() } }
            .onChange(of: model.preset) { _, _ in model.applyPreset() }
            .onChange(of: model.showProcessed) { _, _ in model.updatePlayer() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preset", selection: $model.preset) {
                ForEach(Preset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            ParamSlider(title: "Input gain", value: $model.settings.inputGainDB, range: -12...24, step: 0.5, unit: "dB")

            Toggle("Compressor", isOn: $model.settings.compressor.isEnabled)
            if model.settings.compressor.isEnabled {
                ParamSlider(title: "Threshold", value: $model.settings.compressor.thresholdDB, range: -60...0, step: 1, unit: "dB")
                ParamSlider(title: "Ratio", value: $model.settings.compressor.ratio, range: 1...10, step: 0.5, unit: ":1")
                ParamSlider(title: "Attack", value: $model.settings.compressor.attackMs, range: 1...100, step: 1, unit: "ms")
                ParamSlider(title: "Release", value: $model.settings.compressor.releaseMs, range: 20...1000, step: 10, unit: "ms")
            }

            Toggle("Normalize loudness", isOn: $model.settings.normalize.isEnabled)
            if model.settings.normalize.isEnabled {
                ParamSlider(title: "Target", value: $model.settings.normalize.targetLUFS, range: -24...(-8), step: 0.5, unit: "LUFS")
            }

            Toggle("Limiter", isOn: $model.settings.limiter.isEnabled)
            if model.settings.limiter.isEnabled {
                ParamSlider(title: "Ceiling", value: $model.settings.limiter.ceilingDB, range: -6...0, step: 0.1, unit: "dB")
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var processButton: some View {
        VStack {
            Button {
                model.process()
            } label: {
                Label("Process", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)

            if model.isBusy {
                ProgressView(value: model.progress)
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if let report = model.report, let url = model.resultURL {
            VStack(alignment: .leading, spacing: 8) {
                Text("Loudness: \(format(report.inputLUFS)) -> \(format(report.outputLUFS)) LUFS")
                Text(String(format: "Peak: %.1f -> %.1f dBFS", report.inputPeakDB, report.outputPeakDB))
                Text(String(format: "Max compression: %.1f dB, makeup: %+.1f dB", report.maxCompressionDB, report.makeupDB))
                HStack {
                    Button("Save to Photos") { Task { await model.saveToPhotos() } }
                        .buttonStyle(.bordered)
                    ShareLink(item: url)
                }
            }
            .font(.footnote.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "--"
    }
}

private struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f %@", value, unit)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.footnote)
            Slider(value: $value, in: range, step: step)
        }
    }
}
