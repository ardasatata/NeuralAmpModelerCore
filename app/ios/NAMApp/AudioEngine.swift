import AVFoundation
import Accelerate

/// Manages real-time audio I/O and processes audio through NAM
class AudioEngine: ObservableObject {
    private let bridge: NAMBridge
    private var audioUnit: AUAudioUnit?
    private var auAudioUnit: AudioUnit?

    @Published var isRunning = false
    @Published var sampleRate: Double = 48000.0
    @Published var bufferSize: Int = 256

    init(bridge: NAMBridge) {
        self.bridge = bridge
        setupAudioSession()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure for low-latency playback and record
            try session.setCategory(.playAndRecord,
                                   mode: .default,
                                   options: [.defaultToSpeaker, .allowBluetoothA2DP])

            // Request low latency (~5.8ms at 44.1kHz = 256 samples)
            try session.setPreferredIOBufferDuration(256.0 / 44100.0)

            // Activate the session
            try session.setActive(true)

            // Read back actual values
            sampleRate = session.sampleRate
            let bufferDuration = session.ioBufferDuration
            bufferSize = Int(bufferDuration * sampleRate)

            print("Audio session configured:")
            print("  Sample rate: \(sampleRate) Hz")
            print("  Buffer size: \(bufferSize) frames (\(bufferDuration * 1000.0) ms)")

        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    func start() throws {
        guard !isRunning else { return }

        // Get the actual hardware sample rate
        let hardwareSampleRate = AVAudioSession.sharedInstance().sampleRate

        // Reset NAM bridge with actual sample rate and buffer size
        let maxBufferSize = 4096
        bridge.reset(withSampleRate: hardwareSampleRate, maxBufferSize: Int32(maxBufferSize))

        // Create RemoteIO audio unit for pass-through processing
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "AudioEngine", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to find RemoteIO component"])
        }

        var audioUnit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let audioUnit = audioUnit else {
            throw NSError(domain: "AudioEngine", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio unit"])
        }

        self.auAudioUnit = audioUnit

        // Enable input
        var one: UInt32 = 1
        AudioUnitSetProperty(audioUnit,
                           kAudioOutputUnitProperty_EnableIO,
                           kAudioUnitScope_Input,
                           1,
                           &one,
                           UInt32(MemoryLayout<UInt32>.size))

        // Enable output
        AudioUnitSetProperty(audioUnit,
                           kAudioOutputUnitProperty_EnableIO,
                           kAudioUnitScope_Output,
                           0,
                           &one,
                           UInt32(MemoryLayout<UInt32>.size))

        // Set format
        var format = AudioStreamBasicDescription(
            mSampleRate: hardwareSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        AudioUnitSetProperty(audioUnit,
                           kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Output,
                           1,
                           &format,
                           UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        AudioUnitSetProperty(audioUnit,
                           kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Input,
                           0,
                           &format,
                           UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
                let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
                return engine.renderCallback(ioActionFlags: ioActionFlags,
                                            inTimeStamp: inTimeStamp,
                                            inBusNumber: inBusNumber,
                                            inNumberFrames: inNumberFrames,
                                            ioData: ioData)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        AudioUnitSetProperty(audioUnit,
                           kAudioUnitProperty_SetRenderCallback,
                           kAudioUnitScope_Input,
                           0,
                           &callbackStruct,
                           UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        // Initialize and start
        AudioUnitInitialize(audioUnit)
        AudioOutputUnitStart(audioUnit)

        isRunning = true
        print("Audio engine started")
    }

    private func renderCallback(ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                              inTimeStamp: UnsafePointer<AudioTimeStamp>,
                              inBusNumber: UInt32,
                              inNumberFrames: UInt32,
                              ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let audioUnit = auAudioUnit, let ioData = ioData else { return noErr }

        // Get input audio
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: inNumberFrames * 4,
                mData: nil
            )
        )

        let status = AudioUnitRender(audioUnit,
                                    ioActionFlags,
                                    inTimeStamp,
                                    1,
                                    inNumberFrames,
                                    &bufferList)

        guard status == noErr else { return status }

        // Get input and output buffers
        guard let inputData = bufferList.mBuffers.mData?.assumingMemoryBound(to: Float.self),
              let outputData = ioData.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }

        // Process through NAM
        bridge.processInput(inputData, output: outputData, frameCount: Int32(inNumberFrames))

        return noErr
    }

    func stop() {
        guard isRunning else { return }

        if let audioUnit = auAudioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }

        auAudioUnit = nil
        isRunning = false
        print("Audio engine stopped")
    }

    deinit {
        stop()
    }
}
