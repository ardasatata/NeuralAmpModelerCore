import SwiftUI

struct ContentView: View {
    private let bridge: NAMBridge
    @StateObject private var audioEngine: AudioEngine

    @State private var selectedModel: ModelType = .wavenet
    @State private var bypass = false
    @State private var inputGain: Float = 0.0
    @State private var outputGain: Float = 0.0
    @State private var statusMessage = "No model loaded"
    @State private var isLoading = false

    enum ModelType: String, CaseIterable {
        case wavenet = "Wavenet"
        case lstm = "LSTM"

        var filename: String {
            switch self {
            case .wavenet: return "wavenet"
            case .lstm: return "lstm"
            }
        }
    }

    init() {
        let bridge = NAMBridge()
        self.bridge = bridge
        _audioEngine = StateObject(wrappedValue: AudioEngine(bridge: bridge))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Model")) {
                    Picker("Select Model", selection: $selectedModel) {
                        ForEach(ModelType.allCases, id: \.self) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedModel) { newValue in
                        loadModel(newValue)
                    }

                    Button(action: { loadModel(selectedModel) }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload Model")
                        }
                    }
                    .disabled(isLoading)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }

                Section(header: Text("Audio")) {
                    Toggle("Bypass", isOn: $bypass)
                        .onChange(of: bypass) { newValue in
                            bridge.setBypass(newValue)
                        }

                    Toggle("Processing", isOn: Binding(
                        get: { audioEngine.isRunning },
                        set: { newValue in
                            if newValue {
                                do {
                                    try audioEngine.start()
                                } catch {
                                    statusMessage = "Failed to start audio: \(error.localizedDescription)"
                                }
                            } else {
                                audioEngine.stop()
                            }
                        }
                    ))
                }

                Section(header: Text("Input Gain (\(String(format: "%.1f", inputGain)) dB)")) {
                    Slider(value: $inputGain, in: -12...12, step: 0.5)
                        .onChange(of: inputGain) { newValue in
                            bridge.setInputGain(newValue)
                        }

                    Button("Reset") {
                        inputGain = 0.0
                        bridge.setInputGain(0.0)
                    }
                }

                Section(header: Text("Output Gain (\(String(format: "%.1f", outputGain)) dB)")) {
                    Slider(value: $outputGain, in: -12...12, step: 0.5)
                        .onChange(of: outputGain) { newValue in
                            bridge.setOutputGain(newValue)
                        }

                    Button("Reset") {
                        outputGain = 0.0
                        bridge.setOutputGain(0.0)
                    }
                }

                Section(header: Text("Status")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model:")
                            Spacer()
                            Text(bridge.modelName ?? "None")
                                .foregroundColor(bridge.isModelLoaded ? .green : .red)
                        }

                        HStack {
                            Text("Sample Rate:")
                            Spacer()
                            Text("\(Int(audioEngine.sampleRate)) Hz")
                        }

                        HStack {
                            Text("Buffer Size:")
                            Spacer()
                            Text("\(audioEngine.bufferSize) frames")
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("NAM Audio Processor")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadModel(selectedModel)
        }
    }

    private func loadModel(_ modelType: ModelType) {
        isLoading = true
        statusMessage = "Loading \(modelType.rawValue)..."

        // Load model on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelPath = Bundle.main.path(forResource: modelType.filename, ofType: "nam") else {
                DispatchQueue.main.async {
                    statusMessage = "Model file not found: \(modelType.filename).nam"
                    isLoading = false
                }
                return
            }

            do {
                try bridge.loadModel(modelPath)
                DispatchQueue.main.async {
                    isLoading = false
                    statusMessage = "Loaded \(modelType.rawValue) successfully"
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    statusMessage = "Failed to load model: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
