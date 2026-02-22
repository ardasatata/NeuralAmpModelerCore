import AVFoundation

/// Wrapper around NAMBridge that handles sample rate conversion
class ResamplingBridge {
    private let bridge: NAMBridge
    private var inputConverter: AVAudioConverter?
    private var outputConverter: AVAudioConverter?

    private var modelSampleRate: Double = 48000.0
    private var hardwareSampleRate: Double = 44100.0
    private var needsResampling: Bool = false
    private var isBypassed: Bool = false

    // Pre-allocated buffers for resampling (NO allocation in audio thread!)
    private var hardwareInputBuffer: AVAudioPCMBuffer?
    private var resampledInputBuffer: AVAudioPCMBuffer?
    private var modelOutputBuffer: AVAudioPCMBuffer?
    private var hardwareOutputBuffer: AVAudioPCMBuffer?

    var isModelLoaded: Bool {
        return bridge.isModelLoaded
    }

    var modelName: String? {
        return bridge.modelName
    }

    init(bridge: NAMBridge) {
        self.bridge = bridge
    }

    func loadModel(_ path: String) throws {
        try bridge.loadModel(path)
        updateResamplingState()
    }

    func reset(withSampleRate sampleRate: Double, maxBufferSize: Int32) {
        hardwareSampleRate = sampleRate

        // Get model sample rate before updating state
        modelSampleRate = bridge.modelSampleRate
        if modelSampleRate <= 0 {
            modelSampleRate = 48000.0 // Default assumption
        }

        // Calculate if we need resampling
        let needsResample = abs(modelSampleRate - hardwareSampleRate) >= 1.0

        if needsResample {
            // Reset bridge with MODEL sample rate for proper processing
            let ratio = modelSampleRate / hardwareSampleRate
            let modelMaxBufferSize = Int32(ceil(Double(maxBufferSize) * ratio)) + 128
            bridge.reset(withSampleRate: modelSampleRate, maxBufferSize: modelMaxBufferSize)
        } else {
            // No resampling needed, use hardware rate directly
            bridge.reset(withSampleRate: sampleRate, maxBufferSize: maxBufferSize)
        }

        updateResamplingState()
    }

    func setBypass(_ bypass: Bool) {
        isBypassed = bypass
        bridge.setBypass(bypass)
    }

    func setInputGain(_ gain: Float) {
        bridge.setInputGain(gain)
    }

    func setOutputGain(_ gain: Float) {
        bridge.setOutputGain(gain)
    }

    private func updateResamplingState() {
        guard bridge.isModelLoaded else {
            needsResampling = false
            inputConverter = nil
            outputConverter = nil
            return
        }

        modelSampleRate = bridge.modelSampleRate

        // Check if we need resampling (allow 1 Hz tolerance)
        if abs(modelSampleRate - hardwareSampleRate) < 1.0 {
            needsResampling = false
            inputConverter = nil
            outputConverter = nil
            print("✓ Sample rates match (\(Int(modelSampleRate)) Hz) - no resampling")
            return
        }

        // Create formats
        guard let hwFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareSampleRate,
                channels: 1,
                interleaved: false),
              let modelFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: modelSampleRate,
                channels: 1,
                interleaved: false) else {
            print("⚠️ Failed to create audio formats")
            needsResampling = false
            return
        }

        // Create converters
        inputConverter = AVAudioConverter(from: hwFormat, to: modelFormat)
        outputConverter = AVAudioConverter(from: modelFormat, to: hwFormat)

        if inputConverter != nil && outputConverter != nil {
            needsResampling = true

            // Pre-allocate ALL buffers to avoid real-time allocation
            let maxHardwareFrames = 4096
            let ratio = modelSampleRate / hardwareSampleRate
            let maxModelFrames = Int(ceil(Double(maxHardwareFrames) * ratio)) + 128

            // Hardware rate buffers
            hardwareInputBuffer = AVAudioPCMBuffer(
                pcmFormat: hwFormat,
                frameCapacity: AVAudioFrameCount(maxHardwareFrames)
            )

            hardwareOutputBuffer = AVAudioPCMBuffer(
                pcmFormat: hwFormat,
                frameCapacity: AVAudioFrameCount(maxHardwareFrames)
            )

            // Model rate buffers
            resampledInputBuffer = AVAudioPCMBuffer(
                pcmFormat: modelFormat,
                frameCapacity: AVAudioFrameCount(maxModelFrames)
            )

            modelOutputBuffer = AVAudioPCMBuffer(
                pcmFormat: modelFormat,
                frameCapacity: AVAudioFrameCount(maxModelFrames)
            )

            print("🔄 Resampling enabled: \(Int(hardwareSampleRate)) Hz → \(Int(modelSampleRate)) Hz")
        } else {
            print("⚠️ Failed to create audio converters")
            needsResampling = false
        }
    }

    func processInput(_ input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frameCount: Int32) {
        let frames = Int(frameCount)

        // Bypass: direct passthrough
        if isBypassed {
            memcpy(output, input, frames * MemoryLayout<Float>.size)
            return
        }

        // No resampling needed: process directly through NAM
        if !needsResampling {
            bridge.processInput(input, output: output, frameCount: frameCount)
            return
        }

        // Resampling path - use pre-allocated buffers (NO allocation!)
        guard let inputConverter = inputConverter,
              let outputConverter = outputConverter,
              let hwInput = hardwareInputBuffer,
              let resampledInput = resampledInputBuffer,
              let modelOutput = modelOutputBuffer,
              let hwOutput = hardwareOutputBuffer else {
            // Converters not ready, zero output
            memset(output, 0, frames * MemoryLayout<Float>.size)
            return
        }

        // Copy input to pre-allocated hardware buffer
        hwInput.frameLength = AVAudioFrameCount(frames)
        if let channelData = hwInput.floatChannelData {
            memcpy(channelData[0], input, frames * MemoryLayout<Float>.size)
        }

        // Reset resampled buffer
        resampledInput.frameLength = 0

        // Upsample: hardware rate → model rate
        var error: NSError?
        let inputStatus = inputConverter.convert(to: resampledInput, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return hwInput
        }

        guard inputStatus != .error, resampledInput.frameLength > 0 else {
            memset(output, 0, frames * MemoryLayout<Float>.size)
            return
        }

        // Process through NAM at model sample rate
        guard let resampledInputData = resampledInput.floatChannelData?[0],
              let modelOutputData = modelOutput.floatChannelData?[0] else {
            memset(output, 0, frames * MemoryLayout<Float>.size)
            return
        }

        // Process directly into model output buffer (no intermediate array!)
        bridge.processInput(
            resampledInputData,
            output: modelOutputData,
            frameCount: Int32(resampledInput.frameLength)
        )

        // Set model output length for downsampling
        modelOutput.frameLength = resampledInput.frameLength

        // Downsample: model rate → hardware rate
        let outputStatus = outputConverter.convert(to: hwOutput, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return modelOutput
        }

        guard outputStatus != .error else {
            memset(output, 0, frames * MemoryLayout<Float>.size)
            return
        }

        // Copy resampled output to destination
        if let hwOutputData = hwOutput.floatChannelData {
            let framesToCopy = min(frames, Int(hwOutput.frameLength))
            memcpy(output, hwOutputData[0], framesToCopy * MemoryLayout<Float>.size)

            // Zero any remaining frames
            if framesToCopy < frames {
                memset(output.advanced(by: framesToCopy), 0, (frames - framesToCopy) * MemoryLayout<Float>.size)
            }
        }
    }
}
