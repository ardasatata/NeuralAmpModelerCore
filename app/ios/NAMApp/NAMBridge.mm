#import "NAMBridge.h"

#include <atomic>
#include <cmath>
#include <filesystem>
#include <memory>
#include <vector>

#include "NAM/get_dsp.h"
#include "NAM/dsp.h"

@interface NAMBridge () {
    std::atomic<nam::DSP*> _dsp;
    std::unique_ptr<nam::DSP> _dspOwner;

    double _sampleRate;
    int _maxBufferSize;
    bool _bypass;
    float _inputGainLinear;
    float _outputGainLinear;

    // Conversion buffers for float<->double conversion
    std::vector<NAM_SAMPLE> _inputBuffer;
    std::vector<NAM_SAMPLE> _outputBuffer;
}
@end

@implementation NAMBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _dsp.store(nullptr, std::memory_order_relaxed);
        _sampleRate = 48000.0;
        _maxBufferSize = 512;
        _bypass = NO;
        _inputGainLinear = 1.0f;
        _outputGainLinear = 1.0f;
        _modelName = nil;
    }
    return self;
}

- (BOOL)isModelLoaded {
    return _dsp.load(std::memory_order_acquire) != nullptr;
}

- (BOOL)loadModel:(NSString *)path error:(NSError **)error {
    @try {
        // Load the model on a background thread
        std::filesystem::path modelPath([path UTF8String]);
        auto newDsp = nam::get_dsp(modelPath);

        if (!newDsp) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.neuralampmodeler.NAMApp"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to load NAM model"}];
            }
            return NO;
        }

        // Reset with current settings and prewarm
        newDsp->Reset(_sampleRate, _maxBufferSize);
        newDsp->prewarm();

        // Extract model name (filename without extension)
        NSString *fileName = [path lastPathComponent];
        _modelName = [fileName stringByDeletingPathExtension];

        // Atomic swap: audio thread will see the new pointer immediately
        nam::DSP* oldDsp = _dsp.exchange(newDsp.get(), std::memory_order_acq_rel);
        (void)oldDsp; // Suppress unused variable warning - the old pointer is managed by _dspOwner

        // Transfer ownership
        _dspOwner = std::move(newDsp);

        // Clean up old DSP if any (we do this on the main thread, safe to deallocate)
        // The old pointer is now invalid but we don't need to do anything with it
        // since _dspOwner took ownership of the new one

        // Resize conversion buffers
        _inputBuffer.resize(_maxBufferSize);
        _outputBuffer.resize(_maxBufferSize);

        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.neuralampmodeler.NAMApp"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error loading model"}];
        }
        return NO;
    }
}

- (void)processInput:(const float *)input output:(float *)output frameCount:(int)frameCount {
    nam::DSP* dsp = _dsp.load(std::memory_order_acquire);

    // Bypass mode: just copy input to output
    if (_bypass || !dsp) {
        for (int i = 0; i < frameCount; i++) {
            output[i] = input[i];
        }
        return;
    }

    // Ensure buffers are large enough (resize if needed)
    if (frameCount > _inputBuffer.size()) {
        _inputBuffer.resize(frameCount);
        _outputBuffer.resize(frameCount);
    }

    // Apply input gain and convert float -> NAM_SAMPLE (double or float depending on NAM_SAMPLE_FLOAT)
    for (int i = 0; i < frameCount; i++) {
        _inputBuffer[i] = static_cast<NAM_SAMPLE>(input[i] * _inputGainLinear);
    }

    // Process through NAM
    // Note: DSP::process expects double pointers (pointers to arrays of pointers)
    // For mono processing, we just need a single pointer to our buffer
    NAM_SAMPLE* inputPtr = _inputBuffer.data();
    NAM_SAMPLE* outputPtr = _outputBuffer.data();

    dsp->process(&inputPtr, &outputPtr, frameCount);

    // Apply output gain and convert NAM_SAMPLE -> float
    for (int i = 0; i < frameCount; i++) {
        output[i] = static_cast<float>(_outputBuffer[i] * _outputGainLinear);
    }
}

- (void)resetWithSampleRate:(double)sampleRate maxBufferSize:(int)maxBufferSize {
    _sampleRate = sampleRate;
    _maxBufferSize = maxBufferSize;

    nam::DSP* dsp = _dsp.load(std::memory_order_acquire);
    if (dsp) {
        dsp->Reset(sampleRate, maxBufferSize);
    }

    // Resize conversion buffers
    _inputBuffer.resize(maxBufferSize);
    _outputBuffer.resize(maxBufferSize);
}

- (void)setBypass:(BOOL)bypass {
    _bypass = bypass;
}

- (void)setInputGain:(float)gain {
    // Convert dB to linear
    _inputGainLinear = std::pow(10.0f, gain / 20.0f);
}

- (void)setOutputGain:(float)gain {
    // Convert dB to linear
    _outputGainLinear = std::pow(10.0f, gain / 20.0f);
}

@end
