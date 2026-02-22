# NAM iOS App

Minimal iOS app for real-time Neural Amp Modeler audio processing.

## Architecture

- **NAMBridge.h/mm** - Objective-C++ wrapper around C++ `nam::DSP`
- **ResamplingBridge.swift** - Sample rate conversion wrapper (iOS 48kHz ↔ model rate)
- **AudioEngine.swift** - Core Audio RemoteIO render callback for low-latency I/O
- **ContentView.swift** - SwiftUI interface (model picker, bypass, gain controls)

## Critical Build Requirement: NAM_SAMPLE_FLOAT

**The library and app MUST use matching sample precision.**

### The Problem

NAM supports two sample types (defined in `NAM/dsp.h`):
```cpp
#ifdef NAM_SAMPLE_FLOAT
  #define NAM_SAMPLE float   // 32-bit, 4 bytes per sample
#else
  #define NAM_SAMPLE double  // 64-bit, 8 bytes per sample (DEFAULT)
#endif
```

If the library and app use different types, you get **data corruption**:

1. **Library built with double** (default, 8 bytes)
2. **App expects float** (4 bytes)
3. **Result**: App reads 4 bytes of an 8-byte value → garbage data

**Symptoms**:
- Output values like `36893488147419103232.0` (huge garbage numbers)
- White noise output
- Audio that sounds "bit-crushed" or broken
- `isnan()` / `isinf()` returning false (because it's valid binary, just wrong interpretation)

### The Solution

**Build libNAM.a with NAM_SAMPLE_FLOAT=1:**

```bash
# Device build
cd build_ios
cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-DNAM_SAMPLE_FLOAT=1"
cmake --build . -j4

# Simulator build
cd build_sim
cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-DNAM_SAMPLE_FLOAT=1"
cmake --build . -j4
```

**And ensure the app project.yml has:**
```yaml
GCC_PREPROCESSOR_DEFINITIONS:
  - $(inherited)
  - NAM_SAMPLE_FLOAT=1
```

### Why Float on iOS?

- **Core Audio uses Float32** - All iOS audio APIs use 32-bit floats
- **Performance** - Float math is faster than double on ARM
- **Memory** - Uses half the bandwidth (critical for real-time audio)
- **Precision** - 32-bit float is more than sufficient for audio (24-bit DAC resolution)

## Build & Run

```bash
# Generate Xcode project
cd app/ios
xcodegen generate

# Build for simulator
xcodebuild -project NAMApp.xcodeproj -scheme NAMApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Or open in Xcode
open NAMApp.xcodeproj
```

## Audio Flow

```
[Microphone/Input]
    ↓
[AudioEngine: RemoteIO render callback]
    ↓
[ResamplingBridge: Check sample rate]
    ↓ (if rates match)
[NAMBridge: Process directly]
    ↓
[nam::DSP: Neural network processing]
    ↓
[Output: Speaker/Headphones]
```

## Sample Rate Handling

The app automatically handles sample rate conversion:

1. **Ideal case**: iOS runs at model's rate (usually 48kHz) → **no resampling** (zero latency overhead)
2. **Mismatch**: iOS at 44.1kHz, model at 48kHz → **automatic resampling** via AVAudioConverter

**Forcing a specific rate:**
```swift
// AudioEngine.swift setupAudioSession()
try session.setPreferredSampleRate(48000.0)  // Match most NAM models
```

**Note**: The hardware (e.g., Focusrite interface) may override this.

## Bypass Mode

When bypass is enabled:
- **No NAM processing** - Direct input→output copy
- **No resampling** - Even if sample rates mismatch (lowest latency)
- Used to A/B compare processed vs. clean signal

## Performance Notes

- **Buffer size**: 256 frames @ 48kHz = ~5.3ms latency
- **Real-time safety**: NO allocations in audio thread
  - All buffers pre-allocated during setup
  - Resampling buffers pre-allocated (if needed)
  - Vector resizing only in `reset()`, never in `processInput()`
- **Thread safety**: Atomic pointer swap for model loading (lock-free on audio thread)

## Debugging

If audio sounds wrong, check these in order:

1. **Sample type mismatch** (this document)
2. **Sample rate mismatch** - Check console for "Resampling enabled" vs "rates match"
3. **Model not loaded** - Check for "Loaded successfully" message
4. **Input routing** - Verify audio interface is recognized, not using built-in mic
5. **Buffer sizes** - Ensure `bufSize >= frames` in logs

## Known Limitations

- **Mono only** - Processes single channel (input summed to mono if stereo source)
- **No IR/Cab sim** - Just the amp model (could be added later)
- **Resampling latency** - If sample rates don't match, adds ~2-10ms conversion delay
