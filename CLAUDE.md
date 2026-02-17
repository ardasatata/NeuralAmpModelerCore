# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeuralAmpModelerCore is a C++20 DSP library for neural network-based guitar amplifier modeling. It provides the core audio processing for NAM plugins (see [NeuralAmpModelerPlugin](https://github.com/sdatkinson/NeuralAmpModelerPlugin) for usage). All code lives in the `nam::` namespace.

## Build & Test Commands

```bash
# Build (from repo root)
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j4

# Run tests
./build/tools/run_tests

# Benchmark a model
./build/tools/benchmodel ./example_models/wavenet.nam

# Test loading a model
./build/tools/loadmodel ./example_models/wavenet.nam

# Format code (requires clang-format)
./format.sh
```

CI uses `clang++` on Ubuntu. Tests are compiled with `-O0` to ensure assertions work. Debug builds use `-Werror` with strict warnings (except `dsp.cpp` and `conv1d.cpp` which use `-Wno-error` for Eigen compatibility).

## Architecture

**DSP class hierarchy** (`NAM/dsp.h`): The base `DSP` class defines the audio processing interface. All models implement `process(NAM_SAMPLE** input, NAM_SAMPLE** output, int num_frames)`. Key lifecycle: construct → `Reset(sampleRate, maxBufferSize)` → `process()` in a loop.

**Model implementations:**
- `Linear` (`NAM/dsp.h`) — Simple linear convolution
- `ConvNet` (`NAM/convnet.h`) — Dilated convolutional network with blocks
- `LSTM` (`NAM/lstm.h`) — Multi-layer LSTM, per-frame stateful processing
- `WaveNet` (`NAM/wavenet.h`) — Most complex; dilated convolutions with gating modes (NONE, GATED, BLENDED), FiLM conditioning, residual/skip connections

**Model loading** (`NAM/get_dsp.h`): `nam::get_dsp(path)` parses a `.nam` JSON file and returns a `unique_ptr<DSP>` via the `FactoryRegistry` singleton, which maps architecture names to factory functions.

**Key supporting components:**
- `Conv1D` / `Conv1x1` — Dilated and pointwise convolution layers using ring buffers
- `RingBuffer` — Circular buffer for input history
- `Activation` — Singleton activation functions (Tanh, ReLU, PReLU, etc.) with fast approximations
- `FiLM` — Feature-wise Linear Modulation for conditioning

**Dependencies** (vendored in `Dependencies/`):
- **Eigen** (git submodule) — Linear algebra. Note: alignment issues possible; see README for `EIGEN_MAX_ALIGN_BYTES 0` / `EIGEN_DONT_VECTORIZE` workaround.
- **nlohmann/json** — Header-only JSON parsing for `.nam` files

## Real-Time Safety

A core design constraint: **no heap allocations during `process()`**. Buffers are pre-allocated in `SetMaxBufferSize()`. Tests in `tools/test/` use allocation tracking (`allocation_tracking.h`) to verify this. Any new processing code must maintain this invariant.

## Testing

Tests use plain `assert()` — no external test framework. Test files in `tools/test/` are `#include`'d into `tools/run_tests.cpp`. To add a test, create a file in `tools/test/` and include it in `run_tests.cpp`.

## Code Style

Configured via `.clang-format`: 2-space indent, 120-char column limit, Allman-variant braces (braces on new lines for classes, structs, functions, control statements), `PointerAlignment: Left`.
