#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge between Swift and the C++ NAM DSP library
@interface NAMBridge : NSObject

/// Load a NAM model from the specified file path
/// @param path Full path to the .nam model file
/// @param error Error pointer for error reporting
/// @return YES if the model loaded successfully, NO otherwise
- (BOOL)loadModel:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

/// Process audio through the loaded model
/// @param input Pointer to input audio buffer (interleaved if stereo, but NAM is mono)
/// @param output Pointer to output audio buffer
/// @param frameCount Number of frames to process
- (void)processInput:(const float *)input output:(float *)output frameCount:(int)frameCount;

/// Reset the DSP with the given sample rate and buffer size
/// @param sampleRate Sample rate in Hz
/// @param maxBufferSize Maximum buffer size in frames
- (void)resetWithSampleRate:(double)sampleRate maxBufferSize:(int)maxBufferSize;

/// Set bypass mode (passes input directly to output without processing)
/// @param bypass YES to enable bypass, NO to process through model
- (void)setBypass:(BOOL)bypass;

/// Set input gain (applied before processing)
/// @param gain Input gain in dB (-12 to +12)
- (void)setInputGain:(float)gain;

/// Set output gain (applied after processing)
/// @param gain Output gain in dB (-12 to +12)
- (void)setOutputGain:(float)gain;

/// Check if a model is currently loaded
@property (nonatomic, readonly) BOOL isModelLoaded;

/// Get the name of the currently loaded model (filename without extension)
@property (nonatomic, readonly, copy, nullable) NSString *modelName;

@end

NS_ASSUME_NONNULL_END
