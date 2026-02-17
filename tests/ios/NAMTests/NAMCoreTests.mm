#import <XCTest/XCTest.h>

#include <cmath>
#include <filesystem>
#include <memory>
#include <vector>

#include "NAM/get_dsp.h"
#include "NAM/dsp.h"

static NSString* pathForResource(NSString* name) {
    return [[NSBundle bundleForClass:NSClassFromString(@"NAMCoreTests")]
            pathForResource:[name stringByDeletingPathExtension]
            ofType:[name pathExtension]];
}

@interface NAMCoreTests : XCTestCase
@end

@implementation NAMCoreTests

#pragma mark - Model Loading

- (void)testLoadWavenetModel {
    NSString* path = pathForResource(@"wavenet.nam");
    XCTAssertNotNil(path, @"wavenet.nam not found in test bundle");

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr, @"Failed to load wavenet model");
}

- (void)testLoadLSTMModel {
    NSString* path = pathForResource(@"lstm.nam");
    XCTAssertNotNil(path, @"lstm.nam not found in test bundle");

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr, @"Failed to load LSTM model");
}

#pragma mark - DSP Processing

- (void)testWavenetProcess {
    NSString* path = pathForResource(@"wavenet.nam");
    XCTAssertNotNil(path);

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr);

    const double sampleRate = 48000.0;
    const int numFrames = 64;

    dsp->Reset(sampleRate, numFrames);

    // Create input buffer with a simple sine wave
    std::vector<NAM_SAMPLE> input(numFrames);
    std::vector<NAM_SAMPLE> output(numFrames, 0.0);
    for (int i = 0; i < numFrames; i++) {
        input[i] = 0.5 * std::sin(2.0 * M_PI * 440.0 * i / sampleRate);
    }

    NAM_SAMPLE* inputPtr = input.data();
    NAM_SAMPLE* outputPtr = output.data();
    dsp->process(&inputPtr, &outputPtr, numFrames);

    // Verify output is not all zeros (model should produce something)
    bool hasNonZero = false;
    for (int i = 0; i < numFrames; i++) {
        XCTAssertFalse(std::isnan(output[i]), @"Output contains NaN at frame %d", i);
        XCTAssertFalse(std::isinf(output[i]), @"Output contains Inf at frame %d", i);
        if (std::abs(output[i]) > 1e-10) {
            hasNonZero = true;
        }
    }
    XCTAssertTrue(hasNonZero, @"Output is all zeros — model did not produce audio");
}

- (void)testLSTMProcess {
    NSString* path = pathForResource(@"lstm.nam");
    XCTAssertNotNil(path);

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr);

    const double sampleRate = 48000.0;
    const int numFrames = 64;

    dsp->Reset(sampleRate, numFrames);

    std::vector<NAM_SAMPLE> input(numFrames);
    std::vector<NAM_SAMPLE> output(numFrames, 0.0);
    for (int i = 0; i < numFrames; i++) {
        input[i] = 0.5 * std::sin(2.0 * M_PI * 440.0 * i / sampleRate);
    }

    NAM_SAMPLE* inputPtr = input.data();
    NAM_SAMPLE* outputPtr = output.data();
    dsp->process(&inputPtr, &outputPtr, numFrames);

    bool hasNonZero = false;
    for (int i = 0; i < numFrames; i++) {
        XCTAssertFalse(std::isnan(output[i]), @"Output contains NaN at frame %d", i);
        XCTAssertFalse(std::isinf(output[i]), @"Output contains Inf at frame %d", i);
        if (std::abs(output[i]) > 1e-10) {
            hasNonZero = true;
        }
    }
    XCTAssertTrue(hasNonZero, @"Output is all zeros — model did not produce audio");
}

#pragma mark - Reset & Buffer Sizes

- (void)testResetWithDifferentSampleRates {
    NSString* path = pathForResource(@"wavenet.nam");
    XCTAssertNotNil(path);

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr);

    // Should not crash at different sample rates
    dsp->Reset(44100.0, 128);
    dsp->Reset(48000.0, 256);
    dsp->Reset(96000.0, 512);
}

- (void)testProcessMultipleBuffers {
    NSString* path = pathForResource(@"lstm.nam");
    XCTAssertNotNil(path);

    auto dsp = nam::get_dsp(std::filesystem::path([path UTF8String]));
    XCTAssertTrue(dsp != nullptr);

    const double sampleRate = 48000.0;
    const int numFrames = 128;
    dsp->Reset(sampleRate, numFrames);

    std::vector<NAM_SAMPLE> input(numFrames, 0.1);
    std::vector<NAM_SAMPLE> output(numFrames, 0.0);

    NAM_SAMPLE* inputPtr = input.data();
    NAM_SAMPLE* outputPtr = output.data();

    // Process multiple consecutive buffers (simulates real-time streaming)
    for (int block = 0; block < 10; block++) {
        std::fill(output.begin(), output.end(), 0.0);
        dsp->process(&inputPtr, &outputPtr, numFrames);

        for (int i = 0; i < numFrames; i++) {
            XCTAssertFalse(std::isnan(output[i]), @"NaN at block %d frame %d", block, i);
        }
    }
}

@end
